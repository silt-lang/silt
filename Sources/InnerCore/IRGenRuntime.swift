/// IRGenRuntime.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import LLVM
import Seismography

/// A set of known runtime intrinsic functions declared in the Ferrite headers.
enum RuntimeIntrinsic: String {
  /// The runtime hook for the  copy_value instruction.
  case copyValue = "silt_copyValue"

  /// The runtime hook for the destroy_value instruction.
  case destroyValue = "silt_destroyValue"

  /// The runtime hook for the silt alloc function.
  case alloc  = "silt_alloc"

  /// The runtime hook for the silt alloc function.
  case dealloc  = "silt_dealloc"

  case deallocUninitialized = "silt_dealloc_uninitialized"

  case retain = "silt_retain"

  case release = "silt_release"

  /// The LLVM IR type corresponding to the definition of this function.
  var type: LLVM.FunctionType {
    switch self {
    case .copyValue:
      return LLVM.FunctionType([PointerType.toVoid], PointerType.toVoid)
    case .destroyValue:
      return LLVM.FunctionType([PointerType.toVoid], VoidType())
    case .alloc:
      return LLVM.FunctionType([
        PointerType.toVoid,
        IntType.int64,
        IntType.int64
      ], PointerType.toVoid)
    case .dealloc:
      return LLVM.FunctionType([
        PointerType.toVoid,
        IntType.int64,
        IntType.int64
      ], VoidType())
    case .deallocUninitialized:
      return LLVM.FunctionType([
        PointerType.toVoid,
        IntType.int64,
        IntType.int64
      ], VoidType())
    case .retain:
      return LLVM.FunctionType([PointerType.toVoid], PointerType.toVoid)
    case .release:
      return LLVM.FunctionType([PointerType.toVoid], VoidType())
    }
  }
}

enum MetadataKind: Int {
  case heapLocalVariable = 1
}

final class IRGenRuntime {
  unowned let IGF: IRGenFunction

  init(irGenFunction: IRGenFunction) {
    self.IGF = irGenFunction
  }

  /// Emits a raw heap allocation of a number of bytes, and gives back a
  /// non-NULL pointer.
  /// - parameter bytes: The number of bytes to allocate.
  /// - returns: An LLVM IR value that represents a heap-allocated value that
  ///            must be freed.
  func emitAlloc(
    _ metadata: IRValue, _ size: IRValue, _ align: IRValue
  ) -> IRValue {
    let fn = emitIntrinsic(.alloc)
    return IGF.B.buildCall(fn, args: [metadata, size, align])
  }

  /// Deallocates a heap value allocated via `silt_alloc`.
  /// - parameter value: The heap-allocated value.
  func emitDealloc(_ value: IRValue, _ size: IRValue, _ align: IRValue) {
    let fn = emitIntrinsic(.dealloc)
    _ = IGF.B.buildCall(fn, args: [value, size, align])
  }


  func emitDeallocUninitializedObject(
    _ object: IRValue, _ size: IRValue, _ alignMask: IRValue
  ) {
    let fn = emitIntrinsic(.deallocUninitialized)
    _ = IGF.B.buildCall(fn, args: [ object, size, alignMask ])
  }

  func emitIntrinsic(_ intrinsic: RuntimeIntrinsic) -> Function {
    if let fn = IGF.IGM.module.function(named: intrinsic.rawValue) {
      return fn
    }
    return IGF.B.addFunction(intrinsic.rawValue, type: intrinsic.type)
  }

  func emitCopyValue(_ value: IRValue, name: String = "") -> IRValue {
    let fn = emitIntrinsic(.copyValue)
    return IGF.B.buildCall(fn, args: [value], name: name)
  }

  func emitDestroyValue(_ value: IRValue) {
    let fn = emitIntrinsic(.destroyValue)
    _ = IGF.B.buildCall(fn, args: [value])
  }

  func emitRetain(_ value: IRValue) {
    let fn = emitIntrinsic(.retain)
    _ = IGF.B.buildCall(fn, args: [value])
  }

  func emitRelease(_ value: IRValue) {
    let fn = emitIntrinsic(.release)
    _ = IGF.B.buildCall(fn, args: [value])
  }
}

extension IRGenRuntime {
  /// Emit a dynamic alloca call to allocate enough memory to hold an object of
  /// type 'T' and an optional llvm.stackrestore point if 'isInEntryBlock' is
  /// false.
  func emitDynamicAlloca(_ T: GIRType, _ name: String) -> StackAddress {
    let size = self.emitLoadOfSize(T)
    return self.emitDynamicAlloca(IntType.int8, size, Alignment(16), name)
  }

  func emitDynamicAlloca(
    _ eltTy: IRType, _ arraySize: IRValue, _ align: Alignment, _ name: String
  ) -> StackAddress {
    // Save the stack pointer if we are not in the entry block (we could be
    // executed more than once).
    let isInEntryBlock = (self.IGF.B.insertBlock?.asLLVM()
                          ==
                          self.IGF.function.firstBlock?.asLLVM())
    let stackRestorePoint: IRValue?
    if !isInEntryBlock {
      let sig = LLVM.FunctionType([], PointerType.toVoid)
      let stackSaveFn = self.IGF.B.getOrCreateIntrinsic("llvm.stacksave", sig)

      stackRestorePoint = self.IGF.B.buildCall(stackSaveFn,
                                               args: [], name: "spsave")
    } else {
      stackRestorePoint = nil
    }

    // Emit the dynamic alloca.
    let alloca = self.IGF.B.createAlloca(eltTy, count: arraySize,
                                         alignment: align, name: name)
    assert(!isInEntryBlock)
    return StackAddress(alloca, stackRestorePoint)
  }

  /// Deallocate dynamic alloca's memory if requested by restoring the stack
  /// location before the dynamic alloca's call.
  func emitDeallocateDynamicAlloca(_ address: StackAddress) {
    // Otherwise, call llvm.stackrestore if an address was saved.
    guard let savedSP = address.extraInfo else {
      return
    }

    let sig = LLVM.FunctionType([PointerType.toVoid], VoidType())
    let stackRestoreFn = self.IGF.B.getOrCreateIntrinsic("llvm.stackrestore",
                                                         sig)
    _ = self.IGF.B.buildCall(stackRestoreFn, args: [ savedSP ])
  }
}

enum MangledTypeRefRole {
  case metadata
  case reflection
}

extension IRGenModule {
  func addressOfMangledTypeRef(
    _ type: GIRType, _ role: MangledTypeRefRole
  ) -> IRConstant {
    return PointerType.toVoid.constPointerNull()
  }
}

/// A record layout is the result of laying out a complete structure.
struct RecordLayout {
  /// The kind of object being laid out.
  enum Kind {
    /// A non-heap object does not require a heap header.
    case nonHeapObject

    /// A heap object is destined to be allocated on the heap and must
    /// be emitted with the standard heap header.
    case heapObject

    var requiresHeapHeader: Bool {
      switch self {
      case .nonHeapObject:
        return false
      case .heapObject:
        return true
      }
    }
  }

  /// The statically-known minimum bound on the alignment.
  let minimumAlignment: Alignment

  /// The statically-known minimum bound on the size.
  let minimumSize: Size

  let llvmType: IRType
  let fieldLayouts: [FieldLayout]
  let fieldTypes: [GIRType]

  let wantsFixedLayout: Bool
  let isKnownPOD: Bool

  init(
    _ layoutKind: Kind, _ IGM: IRGenModule,
    _ fieldTypes: [GIRType],
    _ fieldTIs: [TypeInfo], _ typeToFill: StructType? = nil
  ) {
    assert(typeToFill?.isOpaque ?? true)

    let builder = Builder(IGM)

    // Add the heap header if necessary.
    if layoutKind.requiresHeapHeader {
      builder.addHeapHeader()
    }

    let nonEmpty = builder.addFields(fieldTIs)

    // Special-case: there's nothing to store.
    if !nonEmpty {
      assert(builder.isEmpty != layoutKind.requiresHeapHeader)
      self.minimumAlignment = Alignment(1)
      self.minimumSize = Size(0)
      self.wantsFixedLayout = true
      self.isKnownPOD = true
      self.llvmType = typeToFill ?? IGM.opaquePtrTy.pointee
    } else {
      self.minimumAlignment = builder.alignment
      self.minimumSize = builder.size
      self.wantsFixedLayout = builder.wantsFixedLayout
      self.isKnownPOD = builder.isKnownPOD
      if let typeToFill = typeToFill {
        builder.setAsBodyOfStruct(typeToFill)
        self.llvmType = typeToFill
      } else {
        self.llvmType = builder.asAnonymousStruct()
      }
    }
    self.fieldTypes = fieldTypes
    self.fieldLayouts = builder.fieldLayouts
  }

  func emitCastTo(_ IGF: IRGenFunction,
                  _ ptr: IRValue, _ name: String) -> Address {
    let ptrTy = PointerType(pointee: self.llvmType)
    let addr = IGF.B.buildBitCast(ptr, type: ptrTy, name: name)
    return Address(addr, self.minimumAlignment, self.llvmType)
  }

  func emitSize(_ IGM: IRGenModule) -> IRValue {
    return IGM.getSize(self.minimumSize)
  }

  func emitAlignMask(_ IGM: IRGenModule) -> IRValue {
    return IGM.getSize(Size(UInt64(self.minimumAlignment.rawValue - 1)))
  }

  final class Builder {
    let IGM: IRGenModule
    var nextNonFixedOffsetIndex = 0
    var size = Size(0)
    var alignment = Alignment(1)
    var wantsFixedLayout = true
    var isKnownPOD = true
    var structFields = [IRType]()
    var fieldLayouts: [FieldLayout] = []

    init(_ IGM: IRGenModule) {
      self.IGM = IGM
    }

    typealias AddedStorage = Bool
    func addFields(_ typeInfos: [TypeInfo]) -> AddedStorage {
      self.fieldLayouts.reserveCapacity(typeInfos.capacity)

      // Track whether we've added any storage to our layout.
      var addedStorage = false
      for typeInfo in typeInfos {
        let added = self.addField(typeInfo)
        addedStorage = addedStorage || added
      }
      return addedStorage
    }

    func addField(_ eltTI: TypeInfo) -> Bool {
      self.isKnownPOD = self.isKnownPOD && eltTI.isPOD

      // If this element is resiliently- or dependently-sized, record
      // that and configure the ElementLayout appropriately.
      if let fixedTI = eltTI as? FixedTypeInfo {
        guard !fixedTI.isKnownEmpty else {
          self.addEmptyElement(fixedTI)
          // If the element type is empty, it adds nothing.
          self.nextNonFixedOffsetIndex += 1
          return false
        }

        self.addFixedSizeElement(fixedTI)
      } else {
        self.addNonFixedSizeElement(eltTI)
      }
      self.nextNonFixedOffsetIndex += 1
      return true
    }

    func addEmptyElement(_ elt: TypeInfo) {
      self.fieldLayouts.append(FieldLayout(kind: .empty, index: 0,
                                           type: elt, isPOD: elt.isPOD,
                                           byteOffset: 0))
    }

    func addNonFixedSizeElement(_ elt: TypeInfo) {
      // If the element is the first non-empty element to be added to the
      // structure, we can assign it a fixed offset (namely zero) despite
      // it not having a fixed size/alignment.
      guard !self.isEmpty else {
        self.addNonFixedSizeElementAtOffsetZero(elt)
        self.wantsFixedLayout = false
        return
      }

      // Otherwise, we cannot give it a fixed offset, even if all the
      // previous elements are non-fixed.  The problem is not that it has
      // an unknown *size* it's that it has an unknown *alignment*, which
      // might force us to introduce padding.  Absent some sort of user
      // "max alignment" annotation (or having reached the platform
      // maximum alignment, if there is one), these are part and parcel.
      self.wantsFixedLayout = false
      self.addElementAtNonFixedOffset(elt)
    }

    func addHeapHeader() {
      assert(self.structFields.isEmpty,
             "adding heap header at a non-zero offset")
      self.size = IGM.dataLayout.layout(of: IGM.refCountedTy).size
      self.alignment = IGM.getPointerAlignment()
      self.structFields.append(IGM.refCountedTy)
    }


    func addNonFixedSizeElementAtOffsetZero(_ elt: TypeInfo) {
      assert(self.wantsFixedLayout)
      assert(!(elt is FixedTypeInfo))
      assert(self.size == .zero)
      self.fieldLayouts.append(FieldLayout(kind: .initialNonFixed, index: 0,
                                           type: elt, isPOD: elt.isPOD,
                                           byteOffset: 0))
    }

    func addFixedSizeElement(_ eltTI: FixedTypeInfo) {
      // Note that, even in the presence of elements with non-fixed
      // size, we continue to compute the minimum size and alignment
      // requirements of the overall aggregate as if all the
      // non-fixed-size elements were empty.  This gives us minimum
      // bounds on the size and alignment of the aggregate.

      // The struct alignment is the max of the alignment of the fields.
      self.alignment = max(self.alignment, eltTI.alignment)

      // If the current tuple size isn't a multiple of the field's
      // required alignment, we need to pad out.
      let eltAlignment = eltTI.alignment
      let offsetFromAlignment = self.size % eltAlignment
      if offsetFromAlignment != Size(0) {
        let paddingRequired
          = UInt64(eltAlignment.rawValue) - offsetFromAlignment.rawValue
        assert(paddingRequired != 0)

        // Regardless, the storage size goes up.
        self.size += Size(paddingRequired)

        // Add the padding to the fixed layout.
        if self.wantsFixedLayout {
          let paddingTy = ArrayType(elementType: IntType.int8,
                                    count: Int(paddingRequired))
          self.structFields.append(paddingTy)
        }
      }

      // If the overall structure so far has a fixed layout, then add
      // this as a field to the layout.
      if self.wantsFixedLayout {
        self.addElementAtFixedOffset(eltTI)
        // Otherwise, just remember the next non-fixed offset index.
      } else {
        self.addElementAtNonFixedOffset(eltTI)
      }
      self.size += eltTI.fixedSize
    }

    func addElementAtFixedOffset(_ eltTI: FixedTypeInfo) {
      assert(self.wantsFixedLayout)
      self.fieldLayouts.append(FieldLayout(kind: .fixed,
                                           index: structFields.count,
                                           type: eltTI, isPOD: eltTI.isPOD,
                                           byteOffset: self.size))
      self.structFields.append(eltTI.llvmType)
    }

    func addElementAtNonFixedOffset(_ elt: TypeInfo) {
      assert(!self.wantsFixedLayout)
      self.fieldLayouts.append(FieldLayout(kind: .nonFixed,
                                           index: self.nextNonFixedOffsetIndex,
                                           type: elt, isPOD: elt.isPOD,
                                           byteOffset: 0))
    }

    var isEmpty: Bool {
      return self.wantsFixedLayout && self.size == .zero
    }

    func setAsBodyOfStruct(_ type: StructType) {
      assert(type.isOpaque)
      type.setBody(self.structFields, isPacked: true)
      assert(!self.wantsFixedLayout
        || IGM.dataLayout.layout(of: type).size == self.size,
             "LLVM size of fixed struct type does not match StructLayout size")
    }

    func asAnonymousStruct() -> StructType {
      let ty = StructType(elementTypes: self.structFields, isPacked: true,
                          in: self.IGM.module.context)
      assert(!self.wantsFixedLayout
        || self.IGM.dataLayout.layout(of: ty).size == self.size,
             "LLVM size of fixed struct type does not match StructLayout size")
      return ty
    }
  }

}

extension RecordLayout {
  func getPrivateMetadata(
    _ IGM: IRGenModule, _ captureDescriptor: IRConstant
  ) -> IRConstant {
    let dtorFn = self.createDtorFn(IGM, self)
    let kindIdx = MetadataKind.heapLocalVariable.rawValue

    // Build the fields of the private metadata.
    let fty = FunctionType([
      PointerType.toVoid
    ], VoidType())
    let type = StructType(elementTypes: [
      PointerType(pointee: fty),
      PointerType(pointee: PointerType.toVoid),
      StructType(elementTypes: [
        IGM.dataLayout.intPointerType()
      ], isPacked: false, in: IGM.module.context),
      IntType.int32,
      PointerType.toVoid,
    ], isPacked: false, in: IGM.module.context)

    let variable = ConstantBuilder.buildInitializerForStruct(
      in: IGM.module, type: type, named: "metadata",
      alignment: IGM.getPointerAlignment(), linkage: .private) { fields in
      fields.add(dtorFn)
      fields.addNullPointer(PointerType(pointee: PointerType.toVoid))

      fields.beginSubStructure(structTy: StructType(elementTypes: [
        IGM.dataLayout.intPointerType()
      ], isPacked: false, in: IGM.module.context)) { kindStruct in
          kindStruct.add(IGM.dataLayout.intPointerType().constant(kindIdx))
      }

      // Figure out the offset to the first element.
      let elements = self.fieldLayouts
      let offset: Size
      if !elements.isEmpty && elements[0].kind == .fixed {
        offset = elements[0].byteOffset
      } else {
        offset = Size.zero
      }
      fields.addInt32(UInt32(offset.rawValue))

      fields.add(captureDescriptor)
    }

    return variable.constGEP(indices: [
      IntType.int32.constant(0),
      IntType.int32.constant(2)
    ])
  }

  /// Create the destructor function for a layout.
  /// TODO: give this some reasonable name and possibly linkage.
  func createDtorFn(_ IGM: IRGenModule, _ layout: RecordLayout) -> Function {
    let fty = FunctionType([
      PointerType.toVoid
    ], VoidType())
    var fn = IGM.B.addFunction("objectdestroy", type: fty)
    fn.linkage = .private
    fn.callingConvention = .c

    let IGF = IRGenFunction(IGM, fn, fty)
    let structAddr = self.emitCastTo(IGF, fn.parameter(at: 0)!, "")

    struct DynamicHeapOffsets: DynamicOffsets {
      var offsets: [IRValue?] = []
      let totalSize: IRValue?
      let totalAlignmentMask: IRValue

      init(IGF: IRGenFunction, layout: RecordLayout) {
        guard layout.wantsFixedLayout else {
          self.totalSize = layout.emitSize(IGF.IGM)
          self.totalAlignmentMask = layout.emitAlignMask(IGF.IGM)
          return
        }

        // Calculate all the non-fixed layouts.
        // TODO: We could be lazier about this.
        var offset: IRValue?
        var totalAlign: IRValue =
          IGF.IGM.sizeTy.constant(layout.minimumAlignment.rawValue - 1)
        let walk = zip(layout.fieldLayouts, layout.fieldTypes).enumerated()
        for (i, (elt, _)) in walk {
          switch elt.kind {
          case .empty:
            // Don't need to dynamically calculate this offset.
            offsets.append(nil)
          case .fixed:
            // Don't need to dynamically calculate this offset.
            offsets.append(nil)
          case .initialNonFixed:
            // Factor the non-fixed-size field's alignment into the
            // total alignment.
            guard let fixedTI = elt.typeInfo as? FixedTypeInfo else {
              fatalError()
            }
            let alignVal =
              IGF.IGM.sizeTy.constant(Size(fixedTI.fixedAlignment.rawValue - 1))
            totalAlign = IGF.B.buildOr(totalAlign, alignVal)
            offsets.append(nil)
          case .nonFixed:
            // Start calculating non-fixed offsets from the end of the first
            // fixed field.
            var offsetVal = offset ?? initialOffset(IGF, i, layout)

            // Round up to alignment to get the offset.
            guard let eltTI = elt.typeInfo as? FixedTypeInfo else {
              fatalError()
            }
            let alignMask =
              IGF.IGM.sizeTy.constant(eltTI.fixedAlignment.rawValue - 1)
            let notAlignMask = IGF.B.buildNot(alignMask)
            offsetVal = IGF.B.buildAnd(offsetVal, alignMask)
            offsetVal = IGF.B.buildAnd(offsetVal, notAlignMask)

            offsets.append(offsetVal)

            // Advance by the field's size to start the next field.
            offsetVal = IGF.B.buildAdd(offsetVal,
                                       IGF.IGM.sizeTy.constant(eltTI.fixedSize))
            totalAlign = IGF.B.buildOr(totalAlign, alignMask)
            offset = offsetVal
          }
        }
        self.totalSize = offset
        self.totalAlignmentMask = totalAlign
      }

      func offsetForIndex(_ IGF: IRGenFunction, _ index: Int) -> IRValue {
        return self.offsets[index]!
      }
    }

    // Figure out the non-fixed offsets.
    let offsets = DynamicHeapOffsets(IGF: IGF, layout: layout)

    // Destroy the fields.
    for (field, fieldTy) in zip(self.fieldLayouts, self.fieldTypes) {
      guard !field.isPOD else {
        continue
      }

      field.typeInfo.destroy(IGF, field.project(IGF, structAddr, "", offsets),
                             fieldTy)
    }

    IGF.GR.emitDealloc(fn.parameter(at: 0)!,
                       self.emitSize(IGM), self.emitAlignMask(IGM))
    IGF.B.buildRetVoid()

    return fn
  }
}

struct FieldLayout {
  enum Kind {
    case empty
    case fixed
    case nonFixed
    case initialNonFixed
  }

  fileprivate init(
    kind: Kind, index: Int, type: TypeInfo, isPOD: Bool, byteOffset: Size
  ) {
    self.kind = kind
    self.index = index
    self.typeInfo = type
    self.isPOD = isPOD
    self.byteOffset = byteOffset
  }

  let kind: Kind
  let index: Int
  let byteOffset: Size
  let typeInfo: TypeInfo
  let isPOD: Bool

  var isEmpty: Bool {
    return self.kind == .empty
  }

  func project(_ IGF: IRGenFunction, _ baseAddr: Address,
               _ suffix: String, _ offsets: DynamicOffsets?) -> Address {
    switch self.kind {
    case .empty:
      return self.typeInfo.undefAddress()
    case .fixed:
      return IGF.B.createStructGEP(baseAddr, self.index, self.byteOffset,
                                   baseAddr.address.name + suffix)
    case .nonFixed:
      guard let offsets = offsets else {
        fatalError()
      }
      let offset = offsets.offsetForIndex(IGF, self.index)
      return IGF.emitByteOffsetGEP(baseAddr.address, offset, self.typeInfo,
                                   baseAddr.address.name + suffix)
    case .initialNonFixed:
      let ty = PointerType(pointee: self.typeInfo.llvmType)
      return IGF.B.createPointerBitCast(of: baseAddr, to: ty)
    }
  }
}

private func initialOffset(
  _ IGF: IRGenFunction, _ i: Int, _ layout: RecordLayout
) -> IRValue {
  guard i != 0 else {
    let startoffset = layout.minimumSize
    return IGF.IGM.sizeTy.constant(startoffset.valueInBits())
  }
  let prevElt = layout.fieldLayouts[i - 1]
  let prevType = layout.fieldTypes[i - 1]
  // Start calculating offsets from the last fixed-offset field.
  let lastFixedOffset = layout.fieldLayouts[i - 1].byteOffset
  if let fixedType = prevElt.typeInfo as? FixedTypeInfo {
    // If the last fixed-offset field is also fixed-size, we can
    // statically compute the end of the fixed-offset fields.
    let fixedEnd = lastFixedOffset + fixedType.fixedSize
    return IGF.IGM.sizeTy.constant(fixedEnd.valueInBits())
  } else {
    // Otherwise, we need to add the dynamic size to the fixed start
    // offset.
    let offset = IGF.IGM.sizeTy.constant(lastFixedOffset.valueInBits())
    return IGF.B.buildAdd(offset, IGF.GR.emitLoadOfSize(prevType))
  }
}
