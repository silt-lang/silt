/// IRGenGlobal.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography
import LLVM

extension IRGenModule {
  /// Get or create a global variable.
  func getOrCreateGlobalVariable(_ name: String, _ type: IRType) -> IRConstant {
    return self.module.addGlobal(name, type: type)
  }
}

enum ConstantBuilder {
  static func buildInitializerForStruct(
    in module: Module, type: StructType, isPacked: Bool = false,
    named name: String,
    alignment: Alignment,
    linkage: Linkage = .internal,
    addressSpace: Int = 0,
    builder: (ConstantBuilder.Struct) -> Void
  ) -> IRConstant {
    let initBuilder = ConstantBuilder.Initializer(module)
    let structBuilder = ConstantBuilder.Struct(builder: initBuilder,
                                               parent: nil, structTy: type,
                                               isPacked: isPacked)
    builder(structBuilder)
    return structBuilder.finishAndCreateGlobal(name, alignment, true,
                                               linkage, addressSpace)
  }

  static func buildStruct(
    for global: Global, in module: Module, type: StructType,
    isPacked: Bool = false,
    _ builder: (ConstantBuilder.Struct) -> Void
  ) {
    let initBuilder = ConstantBuilder.Initializer(module)
    let structBuilder = ConstantBuilder.Struct(builder: initBuilder,
                                               parent: nil, structTy: type,
                                               isPacked: isPacked)
    builder(structBuilder)
    return structBuilder.finishAndSetAsInitializer(global)
  }

  static func initializeStruct(
    in module: Module, type: StructType, isPacked: Bool = false,
    _ builder: (ConstantBuilder.Struct) -> Void
    ) -> Future {
    let initBuilder = ConstantBuilder.Initializer(module)
    let structBuilder = ConstantBuilder.Struct(builder: initBuilder,
                                               parent: nil, structTy: type,
                                               isPacked: isPacked)
    builder(structBuilder)
    return structBuilder.finishAndCreateFuture()
  }

  static func buildInitializerForAnonymousStruct(
    in module: Module, isPacked: Bool = false,
    _ name: String,
    _ alignment: Alignment,
    _ linkage: Linkage = .internal,
    _ addressSpace: Int = 0,
    _ builder: (ConstantBuilder.Struct) -> Void
  ) -> IRConstant {
    let initBuilder = ConstantBuilder.Initializer(module)
    let structBuilder = ConstantBuilder.Struct(builder: initBuilder,
                                               parent: nil, structTy: nil,
                                               isPacked: isPacked)
    builder(structBuilder)
    return structBuilder.finishAndCreateGlobal(name, alignment, true,
                                               linkage, addressSpace)
  }

  static func buildAnonymousStruct(
    for global: Global, in module: Module, isPacked: Bool = false,
    _ builder: (ConstantBuilder.Struct) -> Void
  ) {
    let initBuilder = ConstantBuilder.Initializer(module)
    let structBuilder = ConstantBuilder.Struct.init(builder: initBuilder,
                                                    parent: nil, structTy: nil,
                                                    isPacked: isPacked)
    builder(structBuilder)
    return structBuilder.finishAndSetAsInitializer(global)
  }

  static func initializeAnonymousStruct(
    in module: Module, isPacked: Bool = false,
    _ builder: (ConstantBuilder.Struct) -> Void
  ) -> Future {
    let initBuilder = ConstantBuilder.Initializer(module)
    let structBuilder = ConstantBuilder.Struct(builder: initBuilder,
                                               parent: nil, structTy: nil,
                                               isPacked: isPacked)
    builder(structBuilder)
    return structBuilder.finishAndCreateFuture()
  }
}

extension ConstantBuilder {
  /// A concrete base class for struct and array aggregate initializer builders.
  class Aggregate {
    fileprivate let initBuilder: ConstantBuilder.Initializer
    fileprivate weak var parent: ConstantBuilder.Aggregate?
    fileprivate let begin: Int
    private var finished = false
    fileprivate var frozen = false
    fileprivate let packed = false

    private struct CachedOffsets {
      let end: Int
      let fromGlobal: Size
    }
    private var cachedOffsets: CachedOffsets = .init(end: 0, fromGlobal: .zero)

    fileprivate init(_ initBuilder: ConstantBuilder.Initializer,
                     _ parent: ConstantBuilder.Aggregate?) {
      self.initBuilder = initBuilder
      self.parent = parent
      self.begin = initBuilder.capacity
      if let parent = parent {
        precondition(!parent.frozen, "parent already has child builder active")
        parent.frozen = true
      } else {
        precondition(!self.initBuilder.frozen,
                     "builder already has child builder active")
        self.initBuilder.frozen = true
      }
    }

    deinit {
      assert(self.finished, "didn't finish aggregate builder")
    }

    func markFinished() {
      self.assertConsistent()
      self.finished = true
      if let parent = parent {
        precondition(parent.frozen,
                     "parent not frozen while child builder active")
        parent.frozen = false
      } else {
        precondition(self.initBuilder.frozen,
                     "builder not frozen while child builder active")
        self.initBuilder.frozen = false
      }
    }

    /// Return the number of elements that have been added to
    /// this struct or array.
    var count: Int {
      self.assertConsistent()
      precondition(self.begin <= self.initBuilder.capacity)
      return self.initBuilder.capacity - self.begin
    }

    var isEmpty: Bool {
      return self.count == 0
    }

    /// Add a new value to this initializer.
    func add(_ value: IRConstant) {
      self.assertConsistent()
      self.initBuilder.appendConstant(value)
    }

    func addSize(_ size: Size) {
      let val = self.initBuilder
                    .dataLayout
                    .intPointerType()
                    .constant(size.valueInBits())
      self.add(val)
    }

    func addInt8(_ value: UInt8) {
      self.add(IntType.int8.constant(value))
    }

    func addInt16(_ value: UInt16) {
      self.add(IntType.int16.constant(value))
    }

    func addInt32(_ value: UInt32) {
      self.add(IntType.int32.constant(value))
    }

    func addNullPointer(_ ptrTy: PointerType) {
      self.add(ptrTy.constPointerNull())
    }

    func add(contentsOf values: [IRConstant]) {
      self.assertConsistent()
      for value in values {
        self.initBuilder.appendConstant(value)
      }
    }

    func addRelativeAddress(to target: IRConstant) {
      self.addRelativeOffset(to: target, type: .int32)
    }

    func addRelativeOffset(to target: IRConstant, type: IntType) {
      self.add(self.getRelativeOffset(type, target))
    }

    func beginSubStructure(structTy: StructType? = nil,
                           isPacked: Bool = false,
                           _ f: (ConstantBuilder.Struct) -> Void) {
      let builder = ConstantBuilder.Struct(builder: self.initBuilder,
                                           parent: self,
                                           structTy: structTy,
                                           isPacked: isPacked)
      f(builder)
      self.add(builder.finalize())
    }

    private func getRelativeOffset(
      _ offsetType: IntType, _ target: IRConstant
    ) -> Constant<Unsigned> {
      let sizeTy = self.initBuilder.dataLayout.intPointerType()

      // Compute the address of the relative-address slot.
      let base = self.addressOfCurrentPosition(offsetType)

      // Subtract.
      let target = Constant<Unsigned>.pointerToInt(target, sizeTy)
      var offset = target - Constant<Unsigned>.pointerToInt(base, sizeTy)

      // Truncate to the relative-address type if necessary.
      if sizeTy.asLLVM() != offsetType.asLLVM() {
        offset = offset.truncate(to: offsetType)
      }

      return offset
    }

    func addressOfCurrentPosition(_ type: IRType) -> IRConstant {
      // Make a global variable.  We will replace this with a GEP to this
      // position after installing the initializer.
      var dummy = self.initBuilder.module.addGlobal("", type: type)
      dummy.linkage = .private
      dummy.isExternallyInitialized = true
      self.initBuilder.appendSelfReference(
        .init(dummy, self.getGEPIndicesToCurrentPosition()))
      return dummy
    }

    /// Return the offset from the start of the initializer to the
    /// next position, assuming no padding is required prior to it.
    ///
    /// This operation will not succeed if any unsized placeholders are
    /// currently in place in the initializer.
    func nextOffsetFromGlobal() -> Size {
      self.assertConsistent()
      return self.offsetFromGlobal(to: self.initBuilder.capacity)
    }

    func getGEPIndicesToCurrentPosition() -> [IRConstant] {
      var result = [IRConstant]()
      self.fillGEP(indices: &result, to: self.initBuilder.capacity)
      return result
    }

    private func fillGEP(indices: inout [IRConstant], to position: Int) {
      // Recurse on the parent builder if present.
      if let parent = self.parent {
        parent.fillGEP(indices: &indices, to: position)
      } else {
        assert(indices.isEmpty)

        // (*Self)
        indices.append(IntType.int32.zero())
      }

      assert(position >= self.begin)
      // [(*member) - (*Self)]
      indices.append(IntType.int32.constant(position - self.begin))
    }

    private func offsetFromGlobal(to end: Int) -> Size {
      var cacheEnd = self.cachedOffsets.end
      assert(cacheEnd <= end)

      // Fast path: if the cache is valid, just use it.
      guard cacheEnd != end else {
        return self.cachedOffsets.fromGlobal
      }

      // If the cached range ends before the index at which the current
      // aggregate starts, recurse for the parent.
      var offset: Size
      if cacheEnd < self.begin {
        assert(cacheEnd == 0)
        guard let parent = self.parent else {
          fatalError("Non-root builder cannot have 0 offset")
        }
        cacheEnd = self.begin
        offset = parent.offsetFromGlobal(to: self.begin)
      } else {
        offset = self.cachedOffsets.fromGlobal
      }

      // Perform simple layout on the elements in cacheEnd..<end.
      if cacheEnd != end {
        let layout = self.initBuilder.dataLayout
        let glob: Size = self.initBuilder.withSubrange(cacheEnd..<end) { elts in
          for element in elts {
            let elementType = element.type
            if !self.packed {
              let alignment: Alignment = layout.abiAlignment(of: elementType)
              offset = TargetData.align(offset, to: alignment)
            }
            offset += layout.storeSize(of: elementType)
          }
          return offset
        }
        self.cachedOffsets = CachedOffsets(end: end, fromGlobal: glob)
      } else {
        // Cache and return.
        self.cachedOffsets = CachedOffsets(end: end, fromGlobal: offset)
      }

      return offset
    }

    private func assertConsistent() {
      precondition(!self.finished,
                   "cannot add more values after finishing builder")
      precondition(!self.frozen, "cannot add values while subbuilder is active")
    }

    // Customization point: subclasses must implement
    fileprivate func finalize() -> IRConstant {
      fatalError("Abstract function must be implemented in subclass")
    }
  }

  final class Struct: ConstantBuilder.Aggregate {
    var structType: StructType?
    let isPacked: Bool

    fileprivate init(builder: ConstantBuilder.Initializer,
                     parent: ConstantBuilder.Aggregate?,
                     structTy: StructType?,
                     isPacked: Bool) {
      self.isPacked = structTy?.isPacked ?? isPacked
      self.structType = structTy
      super.init(builder, parent)
    }

    override func finalize() -> IRConstant {
      self.markFinished()
      return self.initBuilder.finalizeSubrange(from: self.begin) { elts in
        if self.structType == nil && elts.isEmpty {
          self.structType = StructType(elementTypes: [],
                                       isPacked: self.packed,
                                       in: initBuilder.module.context)
        }

        if let ty = self.structType {
          assert(ty.isPacked == self.isPacked)
          return ty.constant(values: [IRConstant](elts))
        } else {
          return StructType.constant(values: [IRConstant](elts))
        }
      }
    }
  }

  fileprivate final class Initializer {
    struct SelfReference {
      let dummy: IRGlobal
      let indices: [IRConstant]

      init(_ dummy: IRGlobal, _ indices: [IRConstant] = []) {
        self.dummy = dummy
        self.indices = indices
      }
    }

    fileprivate let module: Module
    private var buffer: [IRConstant] = []
    fileprivate var selfReferences: [SelfReference] = []
    fileprivate var frozen: Bool = false

    init(_ module: Module) {
      self.module = module
    }

    deinit {
      assert(self.buffer.isEmpty, "didn't claim all values out of buffer")
      assert(self.selfReferences.isEmpty, "didn't apply all self-references")
    }

    var capacity: Int {
      return self.buffer.count
    }

    var dataLayout: TargetData {
      return self.module.dataLayout
    }

    func appendConstant(_ value: IRConstant) {
      self.buffer.append(value)
    }

    func emplaceConstant(_ value: IRConstant, at index: Int) {
      self.buffer[index] = value
    }

    func appendSelfReference(_ ref: SelfReference) {
      self.selfReferences.append(ref)
    }
  }

  enum Future {
    struct IncompleteInitializer {
      fileprivate let get: ConstantBuilder.Initializer

      fileprivate init(_ builder: ConstantBuilder.Initializer) {
        assert(!builder.frozen)
        assert(builder.capacity == 1)
        self.get = builder
      }
    }
    case incomplete(IncompleteInitializer)
    case complete(IRConstant)

    var type: IRType {
      switch self {
      case let .complete(const):
        return const.type
      case let .incomplete(builder):
        return builder.get.withSubrange(0..<1) { range in
          return range[0].type
        }
      }
    }

    func installInGlobal(_ global: Global) {
      switch self {
      case let .complete(const):
        global.initializer = const
      case let .incomplete(builder):
        builder.get.installInGlobal(global)
      }
    }
  }
}

fileprivate extension ConstantBuilder.Struct {
  func finishAndCreateGlobal(
    _ name: String,
    _ alignment: Alignment,
    _ constant: Bool,
    _ linkage: Linkage,
    _ addressSpace: Int) -> Global {
    assert(self.parent == nil, "finishing non-root builder")
    return self.initBuilder.createGlobal(self.finalize(), name, alignment,
                                         constant, linkage, addressSpace)
  }

  func finishAndSetAsInitializer(_ global: Global) {
    assert(self.parent == nil, "finishing non-root builder")
    return self.initBuilder.setGlobalInitializer(global, self.finalize())
  }

  func finishAndCreateFuture() -> ConstantBuilder.Future {
    assert(self.parent == nil, "finishing non-root builder")
    return self.initBuilder.createFuture(self.finalize())
  }
}

fileprivate extension ConstantBuilder.Initializer {
  func createGlobal(
    _ initializer: IRConstant,
    _ name: String,
    _ alignment: Alignment,
    _ constant: Bool = false,
    _ linkage: Linkage = .internal,
    _ addressSpace: Int = 0
  ) -> Global {
    var GV = self.module.addGlobal(name, initializer: initializer,
                                   addressSpace: addressSpace)
    GV.linkage = linkage
    GV.threadLocalModel = .notThreadLocal
    GV.alignment = alignment
    self.resolveSelfReferences(GV)
    return GV
  }

  func createFuture(_ initializer: IRConstant) -> ConstantBuilder.Future {
    assert(self.buffer.isEmpty, "buffer not current empty")
    self.buffer.append(initializer)
    return .incomplete(.init(self))
  }

  func setGlobalInitializer(_ GV: Global, _ initializer: IRConstant) {
    GV.initializer = initializer

    if !self.selfReferences.isEmpty {
      resolveSelfReferences(GV)
    }
  }

  func resolveSelfReferences(_ GV: IRGlobal) {
    for entry in self.selfReferences {
      let resolvedReference = GV.constGEP(indices: entry.indices)
      let dummy = entry.dummy
      dummy.replaceAllUses(with: resolvedReference)
      dummy.eraseFromParent()
    }
    self.selfReferences.removeAll()
  }

  func withSubrange<T>(
    _ range: Range<Int>, _ f: (ArraySlice<IRConstant>) -> T
  ) -> T {
    return f(self.buffer[range])
  }

  func finalizeSubrange(
    from start: Int, _ f: (ArraySlice<IRConstant>) -> IRConstant
  ) -> IRConstant {
    assert(start < self.buffer.endIndex)
    let elts = buffer[start..<buffer.endIndex]
    defer { self.buffer.removeSubrange(start..<buffer.endIndex) }
    return f(elts)
  }

  func installInGlobal(_ global: Global) {
    self.setGlobalInitializer(global, self.buffer[0])
    self.buffer.removeAll()
  }
}
