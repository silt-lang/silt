/// IRCallingConvention.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography
import LLVM

// MARK: Signature Expansion

struct LoweredSignature {
  let type: LLVM.FunctionType

  init(_ IGM: IRGenModule, _ formalType: Seismography.FunctionType) {
    self.type = Builder(IGM, formalType).expandFunctionType()
  }

  private final class Builder {
    let IGM: IRGenModule
    let functionType: Seismography.FunctionType
    var parameterTypes: [IRType]

    init(_ IGM: IRGenModule, _ fnType: Seismography.FunctionType) {
      self.IGM = IGM
      self.functionType = fnType
      self.parameterTypes = []
    }

    /// Expand the components of the primary entrypoint of the function type.
    func expandFunctionType() -> LLVM.FunctionType {
      let resultType = self.expandResult()
      self.expandParameters()
      return .init(argTypes: self.parameterTypes,
                   returnType: resultType,
                   isVarArg: false)
    }

    private func expandResult() -> IRType {
      // swiftlint:disable force_cast
      let fTy = (self.functionType.returnType as! Seismography.FunctionType)
      let resultType = fTy.arguments[0]

      // Fast-path the empty tuple type.
      if let tuple = resultType as? TupleType, tuple.elements.isEmpty {
        return VoidType()
      }

      let native = self.IGM.typeConverter.returnConvention(for: resultType)
      if native.isIndirect {
        return addIndirectResult()
      }

      return native.legalizedType(in: self.IGM.module.context)
    }

    private func expandParameters() {
      self.functionType.arguments.forEach(self.expand)
    }

    private func addIndirectResult() -> IRType {
      // swiftlint:disable force_cast
      let fTy = (self.functionType.returnType as! Seismography.FunctionType)
      let resultType = fTy.arguments[0]
      let resultTI = self.IGM.getTypeInfo(resultType)
      self.parameterTypes.append(PointerType(pointee: resultTI.llvmType))
      return VoidType()
    }

    private func expand(_ girTy: GIRType) {
      let ti = self.IGM.getTypeInfo(girTy)
      let nativeSchema = self.IGM.typeConverter.parameterConvention(for: girTy)
      if nativeSchema.isIndirect {
        self.parameterTypes.append(PointerType(pointee: ti.llvmType))
        return
      }
      if nativeSchema.isEmpty {
        assert(ti.schema.isEmpty)
        return
      }
      let legalTy = nativeSchema.legalizedType(in: self.IGM.module.context)
      for ty in expandScalarOrStructTypeToArray(legalTy) {
        self.parameterTypes.append(ty)
      }
    }
  }
}

// MARK: Aggregate Lowering

struct AggregateLowering {
  let entries: [StorageEntry]

  static let empty = AggregateLowering([])

  private init(_ entries: [StorageEntry]) {
    self.entries = entries
  }

  struct StorageEntry {
    let type: IRType
    let begin: Size
    let end: Size

    fileprivate init(type: IRType, begin: Size, end: Size) {
      self.type = type
      self.begin = begin
      self.end = end
    }

    var extent: (begin: Size, end: Size) {
      return (self.begin, self.end)
    }
  }

  final class Builder {
    enum ProposedStorageRange {
      case concrete(type: IRType, begin: Size, end: Size)
      case opaque(begin: Size, end: Size)

      var stride: Size {
        let (begin, end) = self.extent
        assert(begin <= end)
        return end - begin
      }

      var extent: (begin: Size, end: Size) {
        switch self {
        case let .concrete(type: _, begin: begin, end: end):
          return (begin, end)
        case let .opaque(begin: begin, end: end):
          return (begin, end)
        }
      }

      var isOpaque: Bool {
        switch self {
        case .opaque(begin: _, end: _):
          return true
        default:
          return false
        }
      }

      func asConcreteRange() -> StorageEntry? {
        switch self {
        case let .concrete(type: type, begin: begin, end: end):
          return StorageEntry(type: type, begin: begin, end: end)
        default:
          return nil
        }
      }

      var type: IRType? {
        switch self {
        case let.concrete(type: type, begin: _, end: _):
          return type
        default:
          return nil
        }
      }
    }

    private var layoutEntries = [ProposedStorageRange]()
    private var finalized = false
    private let chunkSize: Size
    private let chunkAlignment: Alignment

    init(_ IGM: IRGenModule) {
      // The layout is split into chunks the size of a pointer.
      self.chunkSize = IGM.dataLayout.pointerSize()
      let alignVal = UInt32(IGM.dataLayout.pointerSize().rawValue)
      self.chunkAlignment = Alignment(alignVal)
    }

    deinit {
      precondition(self.finalized,
                   "builder passed out of scope without being finalized?")
    }

    func append(_ range: ProposedStorageRange) {
      self.layoutEntries.append(range)
    }

    // The merge algorithm for typed layouts is as follows:
    //
    // Consider two typed layouts L and R. A range from L is said to conflict
    // with a range from R if they intersect and they are mapped as different
    // non-empty types. If two ranges conflict, and either range is mapped to
    // a vector, replace it with mapped ranges for the vector elements. If two
    // ranges conflict, and neither range is mapped to a vector, map them both
    // to opaque, combining them with adjacent opaque ranges as necessary. If
    // a range is mapped to a non-empty type, and the bytes in the range are
    // all mapped as empty in the other map, add that range-mapping to the
    // other map. L and R should now match perfectly; this is the result of
    // the merge. Note that this algorithm is both associative and commutative.
    func finalize() -> AggregateLowering {
      precondition(!self.finalized, "Builder was already finalized!")
      defer { self.finalized = true }

      guard !self.layoutEntries.isEmpty else {
        return AggregateLowering.empty
      }

      // Peephole i1
      if let i1Aggregate = self.getAsI1Aggregate() {
        return i1Aggregate
      }

      // First pass: if two entries share a chunk, make them both opaque
      // and stretch one to meet the next.
      guard self.stretchOpaqueEntriesIfNeeeded() else {
        // The rest of the algorithm leaves non-opaque entries alone, so if we
        // have no opaque entries, we're done.
        let concEntries = self.layoutEntries.compactMap({
          $0.asConcreteRange()
        })
        assert(concEntries.count == self.layoutEntries.count)
        return AggregateLowering(concEntries)
      }

      var finalRanges = [StorageEntry]()
      finalRanges.reserveCapacity(self.layoutEntries.count)
      var i = 0
      while i < self.layoutEntries.count {
        defer { i += 1 }

        // Just copy over non-opaque entries.
        if let conc = self.layoutEntries[i].asConcreteRange() {
          finalRanges.append(conc)
          continue
        }

        // Scan forward to determine the full extent of the next opaque range.
        // We know from the first pass that only contiguous ranges will overlap
        // the same aligned chunk.
        var (begin, end) = self.layoutEntries[i].extent
        (i, end) = self.scanForwardToNextNonOpaqueRange(from: i)

        // Add an entry per intersected chunk.
        self.forEachIntersectedChunk(from: begin, to: end) { range in
          finalRanges.append(range)
        }
      }

      return AggregateLowering(finalRanges)
    }

    private func getAsI1Aggregate() -> AggregateLowering? {
      if !self.layoutEntries.allSatisfy({ $0.isOpaque && $0.stride == .one }) {
        return nil
      }

      var ranges = [StorageEntry]()
      ranges.reserveCapacity(self.layoutEntries.count)
      for entry in self.layoutEntries {
        let (begin, end) = entry.extent
        ranges.append(.init(type: IntType.int1, begin: begin, end: end))
      }
      return AggregateLowering(ranges)
    }

    private func stretchOpaqueEntriesIfNeeeded() -> Bool {
      func chunksOverlap(
        _ prevEnd: Size, _ begin: Size, _ align: Alignment
      ) -> Bool {
        return (prevEnd - .one).roundUp(to: align) == begin.roundUp(to: align)
      }

      var hasOpaqueEntries = self.layoutEntries[0].isOpaque
      for i in self.layoutEntries.indices.dropFirst() {
        let (prevBegin, prevEnd) = self.layoutEntries[i - 1].extent
        let (curBegin, curEnd) = self.layoutEntries[i].extent
        if chunksOverlap(prevEnd, curBegin, chunkAlignment) {
          self.layoutEntries[i - 1] = .opaque(begin: prevBegin, end: curBegin)
          self.layoutEntries[i] = .opaque(begin: curBegin, end: curEnd)
          hasOpaqueEntries = true
        } else if self.layoutEntries[i].isOpaque {
          hasOpaqueEntries = true
        }
      }
      return hasOpaqueEntries
    }

    private func scanForwardToNextNonOpaqueRange(
      from start: Int
    ) -> (Int, Size) {
      precondition(self.layoutEntries[start].isOpaque)

      var i = start
      var (_, end) = self.layoutEntries[i].extent
      while i + 1 != self.layoutEntries.count {
        let (nextBegin, nextEnd) = self.layoutEntries[i + 1].extent
        guard self.layoutEntries[i + 1].isOpaque && end == nextBegin else {
          break
        }

        end = nextEnd
        i += 1
      }
      return (i, end)
    }

    private func forEachIntersectedChunk(
      from start: Size, to end: Size, _ fill: (StorageEntry) -> Void
    ) {
      var begin = start
      repeat {
        // Find the smallest aligned storage unit in the maximal aligned
        // storage unit containing 'begin' that contains all the bytes in
        // the intersection between the range and this chunk.
        let localBegin = begin
        let chunkBegin = localBegin.roundUp(to: chunkAlignment)
        let chunkEnd = chunkBegin + chunkSize
        let localEnd = min(end, chunkEnd)

        // Just do a simple loop over ever-increasing unit sizes.
        var unitSize = Size.one
        var unitBegin = Size.zero
        var unitEnd = Size.zero
        while true {
          assert(unitSize <= chunkSize)
          // Reinterpret the chunk size as an alignment value and round up.
          let chunkAlign = Alignment(UInt32(unitSize.rawValue))
          unitBegin = localBegin.roundUp(to: chunkAlign)
          unitEnd = unitBegin + unitSize
          guard unitEnd < localEnd else {
            break
          }
          unitSize *= Size(2)
        }

        // Add an entry for this unit.
        let entryTy = IntType(width: Int(unitSize.valueInBits()))
        fill(.init(type: entryTy, begin: unitBegin, end: unitEnd))

        // The next chunk starts where this chunk left off.
        begin = localEnd
      } while begin != end
    }
  }

  var isEmpty: Bool {
    return self.entries.isEmpty
  }
}

// MARK: Calling Convention

struct NativeConvention {
  let lowering: AggregateLowering
  let isIndirect: Bool
  let isReturn: Bool

  init(_ IGM: IRGenModule, _ ti: TypeInfo, _ isReturn: Bool) {
    let lowering = AggregateLowering.Builder(IGM)
    self.isReturn = isReturn
    guard let loadable = ti as? LoadableTypeInfo else {
      self.lowering = lowering.finalize()
      self.isIndirect = true
      return
    }
    loadable.buildAggregateLowering(IGM, lowering, .zero)
    self.lowering = lowering.finalize()
    self.isIndirect =  false //lowering.shouldPassIndirectly(isReturn)
  }

  var isEmpty: Bool {
    return self.lowering.isEmpty
  }

  var count: Int {
    return self.lowering.entries.count
  }

  func legalizedType(in context: Context) -> IRType {
    guard let first = self.lowering.entries.first else {
      return VoidType()
    }

    guard self.lowering.entries.count > 1 else {
      return first.type
    }

    return StructType(elementTypes: self.lowering.entries.map { $0.type },
                      isPacked: false, in: context)
  }
}

private func expandScalarOrStructTypeToArray(_ ty: IRType) -> [IRType] {
  guard let sty = ty as? StructType else {
    return [ty]
  }
  return sty.elementTypes
}

private func sizesMatch(_ t1: IRType, _ t2: IRType, _ td: TargetData) -> Bool {
  return td.sizeOfTypeInBits(t1) == td.sizeOfTypeInBits(t2)
}
