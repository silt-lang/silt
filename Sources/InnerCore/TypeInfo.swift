/// TypeInfo.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import LLVM
import Seismography

// MARK: Basic Type Info

/// A type that provides the IR-level implementation details for a type.
///
// swiftlint:disable line_length
protocol TypeInfo: Explodable, Assignable, Destroyable, StackAllocatable, PODable {
  /// The LLVM representation of a stored value of this type.  For
  /// non-fixed types, this is really useful only for forming pointers to it.
  var llvmType: IRType { get }
  /// The minimum alignment of a value of this type.
  var alignment: Alignment { get }
}

extension TypeInfo {
  /// Computes and returns the explosion schema for values of this type.
  var schema: Explosion.Schema {
    let s = Explosion.Schema.Builder()
    self.buildExplosionSchema(s)
    return s.finalize()
  }

  /// Crafts an address value from an IR value with the same underlying type
  /// as this type info object.
  ///
  /// If the pointer's underlying type does not match this type info, a fatal
  /// error is raised.
  ///
  /// FIXME: Opaque pointers make this invariant useless.
  ///
  /// - Parameter v: A value of pointer type.
  /// - Returns: An address value for the pointer value.
  func address(for v: IRValue) -> Address {
    guard let ptrTy = v.type as? PointerType else {
      fatalError()
    }
    precondition(ptrTy.pointee.asLLVM() == self.llvmType.asLLVM())
    return Address(v, self.alignment, self.llvmType)
  }

  /// Computes an address value for an `undef` pointer value to the underlying
  /// type of this type info object.
  ///
  /// - Returns: The address value of an `undef` pointer.
  func undefAddress() -> Address {
    return Address(PointerType(pointee: self.llvmType).undef(), self.alignment, self.llvmType)
  }
}

/// A refinement of `TypeInfo` for those types with a known internal layout.
///
/// Implementing this protocol frees you from having to provide an `alignment`
/// accessor.  Types should implement the `fixedAlignment` accessor instead.
protocol FixedTypeInfo: TypeInfo {
  /// The exact size of values of the underlying type.
  var fixedSize: Size { get }

  /// The exact alignment of values of the underlying type.
  var fixedAlignment: Alignment { get }

  /// Whether the underlying type is known to require no bits to represent.
  var isKnownEmpty: Bool { get }
}

extension FixedTypeInfo {
  var alignment: Alignment {
    return self.fixedAlignment
  }
}

extension FixedTypeInfo {
  func allocateStack(_ IGF: IRGenFunction, _ : GIRType) -> StackAddress {
    guard !self.isKnownEmpty else {
      return StackAddress(self.undefAddress())
    }

    let alloca = IGF.B.createAlloca(self.llvmType, alignment: self.alignment)
    _ = IGF.B.createLifetimeStart(alloca, self.fixedSize)
    return StackAddress(alloca)
  }

  func deallocateStack(_ IGF: IRGenFunction, _ adr: StackAddress, _ : GIRType) {
    guard !self.isKnownEmpty else {
      return
    }
    _ = IGF.B.createLifetimeEnd(adr.address, self.fixedSize)
  }
}

// MARK: Loadable Type Info

/// A refinement of `TypeInfo` that describes values where load and store are
/// well-defined operations.
protocol LoadableTypeInfo: FixedTypeInfo, Loadable, Aggregable { }

/// The implementation of type info for an object with zero size and alignment.
///
/// All operations on this type are a no-op.
final class EmptyTypeInfo: LoadableTypeInfo {
  let fixedSize: Size = .zero
  let llvmType: IRType

  var fixedAlignment: Alignment {
    return Alignment.one
  }

  var isKnownEmpty: Bool {
    return true
  }

  init(_ ty: IRType) {
    self.llvmType = ty
  }

  func buildExplosionSchema(_ : Explosion.Schema.Builder) { }
  func buildAggregateLowering(_ : IRGenModule,
                              _ : AggregateLowering.Builder, _ : Size) { }
  func explosionSize() -> Int { return 0 }
  func initialize(_ : IRGenFunction, _ : Explosion, _ : Address) { }
  func loadAsCopy(_ : IRGenFunction, _ : Address, _ : Explosion) { }
  func loadAsTake(_ : IRGenFunction, _ : Address, _ : Explosion) { }
  func copy(_ : IRGenFunction, _ : Explosion, _ : Explosion) { }
  func consume(_ : IRGenFunction, _ : Explosion) { }
  func reexplode(_ : IRGenFunction, _ : Explosion, _ : Explosion) { }
  func packIntoPayload(_ : IRGenFunction, _ : Payload,
                       _ : Explosion, _ : Size) { }
  func unpackFromPayload(_ : IRGenFunction, _ : Payload,
                         _ : Explosion, _ : Size) { }
  func destroy(_ : IRGenFunction, _ : Address, _ : GIRType) { }
  func assign(_ : IRGenFunction, _ : Explosion, _ : Address) { }
  func assignWithCopy(_ : IRGenFunction,
                      _ : Address, _ : Address, _ : GIRType) { }
}

// MARK: Indirect Type Info

/// A refinement of `TypeInfo` for types with an indirect representation.
///
/// This can be useful in situations where an aggregate may not be entirely
/// loadable, but still has a fixed layout.  Note that `FixedTypeInfo` is not
/// a requirement.
protocol IndirectTypeInfo: TypeInfo { }

extension IndirectTypeInfo {
  func buildExplosionSchema(_ schema: Explosion.Schema.Builder) {
    schema.append(.aggregate(self.llvmType, self.alignment))
  }
}

// MARK: Runtime Type Info

/// A refinement of `TypeInfo` for types that require the Silt runtime to
/// manipulate their values.  Very little static information is known about
/// these types.
protocol WitnessSizedTypeInfo: IndirectTypeInfo { }

extension WitnessSizedTypeInfo {
  func allocateStack(_ IGF: IRGenFunction, _ T: GIRType) -> StackAddress {
    let alloca = IGF.GR.emitDynamicAlloca(T, "")
    IGF.B.createLifetimeStart(alloca.address)
    let ptrTy = PointerType(pointee: self.llvmType)
    let addr = IGF.B.createPointerBitCast(of: alloca.address, to: ptrTy)
    return alloca.withAddress(addr)
  }

  func deallocateStack(_ IGF: IRGenFunction,
                       _ addr: StackAddress, _ type: GIRType) {
    IGF.B.createLifetimeEnd(addr.address)
    IGF.GR.emitDeallocateDynamicAlloca(addr)
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) {
    IGF.GR.emitDestroyCall(type, addr)
  }

  func assignWithCopy(_ IGF: IRGenFunction,
                      _ dest: Address, _ src: Address, _ type: GIRType) {
    IGF.GR.emitAssignWithCopyCall(type, dest, src)
  }
}

// MARK: Data Type Info

/// The concrete implementation of type information for a fixed-layout data
/// type.
final class FixedDataTypeTypeInfo: Strategizable, FixedTypeInfo {
  let llvmType: IRType
  let strategy: DataTypeStrategy
  let fixedSize: Size
  let fixedAlignment: Alignment

  var isKnownEmpty: Bool {
    return self.fixedSize == .zero
  }

  init(_ strategy: DataTypeStrategy, _ llvmType: StructType,
       _ size: Size, _ align: Alignment) {
    self.strategy = strategy
    self.fixedSize = size
    self.llvmType = llvmType
    self.fixedAlignment = align
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) {
    self.strategy.destroy(IGF, addr, type)
  }

  func assignWithCopy(_ IGF: IRGenFunction,
                      _ dest: Address, _ src: Address, _ type: GIRType) {
    self.strategy.assignWithCopy(IGF, dest, src, type)
  }
}

/// The concrete implementation of type information for a loadable data
/// type.
final class LoadableDataTypeTypeInfo: Strategizable, LoadableTypeInfo {
  let strategy: DataTypeStrategy
  let fixedSize: Size
  let llvmType: IRType
  let fixedAlignment: Alignment

  init(_ strategy: DataTypeStrategy, _ llvmType: StructType,
       _ size: Size, _ align: Alignment) {
    self.strategy = strategy
    self.fixedSize = size
    self.llvmType = llvmType
    self.fixedAlignment = align
  }

  var isKnownEmpty: Bool {
    return self.fixedSize == .zero
  }

  func buildAggregateLowering(_ IGM: IRGenModule,
                              _ builder: AggregateLowering.Builder,
                              _ offset: Size) {
    self.strategy.buildAggregateLowering(IGM, builder, offset)
  }

  func copy(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    self.strategy.copy(IGF, src, dest)
  }

  func explosionSize() -> Int {
    return self.strategy.explosionSize()
  }

  func reexplode(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    return self.strategy.reexplode(IGF, src, dest)
  }

  func initialize(_ IGF: IRGenFunction, _ from: Explosion, _ addr: Address) {
    return self.strategy.initialize(IGF, from, addr)
  }

  func loadAsCopy(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    self.strategy.loadAsCopy(IGF, addr, explosion)
  }

  func loadAsTake(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    self.strategy.loadAsTake(IGF, addr, explosion)
  }

  func consume(_ IGF: IRGenFunction, _ explosion: Explosion) {
    self.strategy.consume(IGF, explosion)
  }

  func packIntoPayload(_ IGF: IRGenFunction, _ payload: Payload,
                       _ source: Explosion, _ offset: Size) {
    self.strategy.packIntoPayload(IGF, payload, source, offset)
  }

  func unpackFromPayload(_ IGF: IRGenFunction, _ payload: Payload,
                         _ destination: Explosion, _ offset: Size) {
    self.strategy.unpackFromPayload(IGF, payload, destination, offset)
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) {
    self.strategy.destroy(IGF, addr, type)
  }

  func assign(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Address) {
    self.strategy.assign(IGF, src, dest)
  }

  func assignWithCopy(_ IGF: IRGenFunction,
                      _ dest: Address, _ src: Address, _ type: GIRType) {
    self.strategy.assignWithCopy(IGF, dest, src, type)
  }
}

/// The concrete implementation of type information for a runtime-sized data
/// type.
final class DynamicDataTypeTypeInfo: Strategizable, WitnessSizedTypeInfo {
  let strategy: DataTypeStrategy
  let llvmType: IRType
  let alignment: Alignment

  init(_ strategy: DataTypeStrategy, _ irTy: IRType, _ align: Alignment) {
    self.strategy = strategy
    self.llvmType = irTy
    self.alignment = align
  }

  func buildExplosionSchema(_ schema: Explosion.Schema.Builder) {
    self.strategy.buildExplosionSchema(schema)
  }

  func allocateStack(_ IGF: IRGenFunction, _ T: GIRType) -> StackAddress {
    let alloca = IGF.GR.emitDynamicAlloca(T, "")
    IGF.B.createLifetimeStart(alloca.address)
    let ptrTy = PointerType(pointee: self.llvmType)
    let addr = IGF.B.createPointerBitCast(of: alloca.address, to: ptrTy)
    return alloca.withAddress(addr)
  }

  func deallocateStack(_ IGF: IRGenFunction,
                       _ addr: StackAddress, _ type: GIRType) {
    IGF.B.createLifetimeEnd(addr.address)
    IGF.GR.emitDeallocateDynamicAlloca(addr)
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) {
    self.strategy.destroy(IGF, addr, type)
  }

  func assignWithCopy(_ IGF: IRGenFunction,
                      _ dest: Address, _ src: Address, _ type: GIRType) {
    self.strategy.assignWithCopy(IGF, dest, src, type)
  }
}

// MARK: Heap Type Info

/// A refinement of `TypeInfo` for types whose representation is a single
/// heap pointer value.
protocol HeapTypeInfo: LoadableTypeInfo, SingleScalarizable { }

extension HeapTypeInfo {
  static var isPOD: Bool {
    return false
  }
}

/// The concrete implementation of type information for an object value managed
/// by the Silt runtime.
final class ManagedObjectTypeInfo: HeapTypeInfo {
  static let isPOD: Bool = false

  let fixedSize: Size
  let fixedAlignment: Alignment
  var isKnownEmpty: Bool {
    return false
  }
  var isPOD: Bool {
    return false
  }
  let llvmType: IRType

  init(_ storage: PointerType, _ size: Size, _ align: Alignment) {
    self.llvmType = storage
    self.fixedSize = size
    self.fixedAlignment = align
  }

  func explosionSize() -> Int {
    return 1
  }

  func initialize(_ IGF: IRGenFunction, _ from: Explosion, _ addr: Address) {
    IGF.B.buildStore(from.claimSingle(), to: addr.address)
  }

  func loadAsCopy(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    let value = IGF.B.createLoad(addr)
    self.emitScalarRetain(IGF, value)
    explosion.append(value)
  }

  func loadAsTake(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    explosion.append(IGF.B.createLoad(addr))
  }

  func copy(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    let value = src.claimSingle()
    self.emitScalarRetain(IGF, value)
    dest.append(value)
  }

  func consume(_ IGF: IRGenFunction, _ explosion: Explosion) {
    let value = explosion.claimSingle()
    self.emitScalarRelease(IGF, value)
  }

  func buildAggregateLowering(_ IGM: IRGenModule,
                              _ lowering: AggregateLowering.Builder,
                              _ offset: Size) {
    let end =  offset + IGM.dataLayout.storeSize(of: self.llvmType)
    lowering.append(.concrete(type: self.llvmType, begin: offset, end: end))
  }

  func reexplode(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    let size = self.explosionSize()
    src.transfer(into: dest, size)
  }

  func packIntoPayload(_ IGF: IRGenFunction, _ payload: Payload,
                       _ source: Explosion, _ offset: Size) {
    payload.insertValue(IGF, source.claimSingle(), offset)
  }

  func unpackFromPayload(_ IGF: IRGenFunction, _ payload: Payload,
                         _ destination: Explosion, _ offset: Size) {
    destination.append(payload.extractValue(IGF, self.llvmType, offset))
  }

  func buildExplosionSchema(_ schema: Explosion.Schema.Builder) {
    schema.append(.scalar(self.llvmType))
  }

  func destroy(_ IGF: IRGenFunction,
               _ addr: Address, _ type: GIRType) {
    let value = IGF.B.createLoad(addr,
                                 alignment: addr.alignment, name: "toDestroy")
    self.emitScalarRelease(IGF, value)
  }

  func assignWithCopy(_ IGF: IRGenFunction,
                      _ dest: Address, _ src: Address, _ : GIRType) {
    let temp = Explosion()
    self.loadAsCopy(IGF, src, temp)
    self.assign(IGF, temp, dest)
  }
}

// MARK: Box Type Info

/// A refinement of heap type information for a `Box`ed value.  The underlying
/// representation is opaque, and its lifetime is managed by the Silt
/// runtime.  Unlike a `ManagedObject` value, a box may only be manipulated
/// indirectly: its address must be projected, and allocation and deallocation
/// routines are provided by the Silt runtime.
protocol BoxTypeInfo: HeapTypeInfo {
  /// Allocate a box of the given type.
  ///
  /// This function is used to implement the `alloc_box` instruction.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - boxedType: The underlying type to allocate a box for.
  /// - Returns: An owned address value representing the address of
  ///   the boxed value.
  func allocate(_ IGF: IRGenFunction, _ boxedType: GIRType) -> OwnedAddress

  /// Deallocate a box of the given type.
  ///
  /// This function is used to implement the `dealloc_box` instruction.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - box: The box value.
  ///   - boxedType: The underlying type to deallocate a box for.
  func deallocate(_ IGF: IRGenFunction, _ box: IRValue, _ boxedType: GIRType)

  /// Project the address value from a box.
  ///
  /// This function is used to implement the `project_box` instruction.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - box: The box value.
  ///   - boxedType: The underlying type to allocate a box for.
  /// - Returns: An address value describing the the projected value of the box.
  func project(_ IGF: IRGenFunction,
               _ box: IRValue, _ boxedType: GIRType) -> Address
}

extension BoxTypeInfo {
  func explosionSize() -> Int {
    return 1
  }

  func initialize(_ IGF: IRGenFunction, _ from: Explosion, _ addr: Address) {
    IGF.B.buildStore(from.claimSingle(), to: addr.address)
  }

  func loadAsCopy(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    let value = IGF.B.createLoad(addr)
    self.emitScalarRetain(IGF, value)
    explosion.append(value)
  }

  func loadAsTake(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    explosion.append(IGF.B.createLoad(addr))
  }

  func copy(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    let value = src.claimSingle()
    self.emitScalarRetain(IGF, value)
    dest.append(value)
  }

  func consume(_ IGF: IRGenFunction, _ explosion: Explosion) {
    let value = explosion.claimSingle()
    self.emitScalarRelease(IGF, value)
  }

  func buildAggregateLowering(_ IGM: IRGenModule,
                              _ builder: AggregateLowering.Builder,
                              _ offset: Size) {
    let end = offset + IGM.dataLayout.storeSize(of: self.llvmType)
    builder.append(.concrete(type: self.llvmType, begin: offset, end: end))
  }

  func reexplode(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    let size = self.explosionSize()
    src.transfer(into: dest, size)
  }

  func packIntoPayload(_ IGF: IRGenFunction, _ payload: Payload,
                       _ source: Explosion, _ offset: Size) {
    payload.insertValue(IGF, source.claimSingle(), offset)
  }

  func unpackFromPayload(_ IGF: IRGenFunction, _ payload: Payload,
                         _ destination: Explosion, _ offset: Size) {
    destination.append(payload.extractValue(IGF, self.llvmType, offset))
  }

  func buildExplosionSchema(_ schema: Explosion.Schema.Builder) {
    schema.append(.scalar(self.llvmType))
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) {
    let value = IGF.B.createLoad(addr,
                                 alignment: addr.alignment, name: "toDestroy")
    self.emitScalarRelease(IGF, value)
  }

  func assignWithCopy(_ IGF: IRGenFunction,
                      _ dest: Address, _ src: Address, _ : GIRType) {
    let temp = Explosion()
    self.loadAsCopy(IGF, src, temp)
    self.assign(IGF, temp, dest)
  }
}

/// Concrete type information for an empty boxed value.
///
/// All operations on values of an empty box are implemented in terms
/// of `undef`.
final class EmptyBoxTypeInfo: BoxTypeInfo {
  let llvmType: IRType
  let fixedSize: Size
  let fixedAlignment: Alignment

  var isKnownEmpty: Bool {
    return false
  }

  var isPOD: Bool {
    return true
  }

  init(_ IGM: IRGenModule) {
    self.fixedSize = IGM.getPointerSize()
    self.fixedAlignment = IGM.getPointerAlignment()
    self.llvmType = IGM.refCountedPtrTy
  }

  func allocate(_ IGF: IRGenFunction, _ boxedType: GIRType) -> OwnedAddress {
    return OwnedAddress(IGF.getTypeInfo(boxedType).undefAddress(),
                        IGF.emitAllocEmptyBoxCall())
  }

  func deallocate(_ IGF: IRGenFunction, _ box: IRValue, _ boxedType: GIRType) {
  }

  func project(_ IGF: IRGenFunction,
               _ box: IRValue, _ boxedType: GIRType) -> Address {
    return IGF.getTypeInfo(boxedType).undefAddress()
  }
}

/// Provides type information about a boxed value where the underlying type has
/// a fixed layout.
///
/// In this case, we can often choose to skip a level of indirection and
/// allocate the box header in-line with the data for the boxed value.
final class FixedBoxTypeInfo: FixedHeapLayout, BoxTypeInfo {
  let llvmType: IRType
  let fixedSize: Size
  let fixedAlignment: Alignment
  let layout: RecordLayout

  var isKnownEmpty: Bool {
    return self.fixedSize == .zero
  }

  var isPOD: Bool {
    return false
  }

  init(_ IGM: IRGenModule, _ type: GIRType) {
    self.layout = RecordLayout(.heapObject, IGM,
                               [type], [IGM.getTypeInfo(type)])
    self.fixedSize = IGM.getPointerSize()
    self.fixedAlignment = IGM.getPointerAlignment()
    self.llvmType = IGM.refCountedPtrTy
  }
}

/// Provides type information about a boxed value where the underlying type
/// has a dynamic layout.
///
/// As the underlying value must be manipulated indirectly, the box is
/// implemented as a reference-counted pointer.
final class NonFixedBoxTypeInfo: BoxTypeInfo {
  let llvmType: IRType
  let fixedSize: Size
  let fixedAlignment: Alignment

  var isKnownEmpty: Bool {
    return false
  }

  var isPOD: Bool {
    return false
  }

  init(_ IGM: IRGenModule) {
    self.llvmType = IGM.refCountedPtrTy
    self.fixedSize = IGM.getPointerSize()
    self.fixedAlignment = IGM.getPointerAlignment()
  }

  func allocate(_ IGF: IRGenFunction, _ boxedType: GIRType) -> OwnedAddress {
    let ti = IGF.getTypeInfo(boxedType)
    let metadata = IGF.emitTypeMetadataRefForLayout(boxedType)
    let (box, address) = IGF.emitAllocBoxCall(metadata)
    let ptrTy = PointerType(pointee: ti.llvmType)
    let castAddr = IGF.B.createPointerBitCast(of: address, to: ptrTy)
    return OwnedAddress(castAddr, box)
  }

  func deallocate(_ IGF: IRGenFunction, _ box: IRValue, _ boxedType: GIRType) {
    let metadata = IGF.emitTypeMetadataRefForLayout(boxedType)
    IGF.emitDeallocBoxCall(box, metadata)
  }

  func project(_ IGF: IRGenFunction,
               _ box: IRValue, _ boxedType: GIRType) -> Address {
    let ti = IGF.getTypeInfo(boxedType)
    let metadata = IGF.emitTypeMetadataRefForLayout(boxedType)
    let address = IGF.B.buildBitCast(IGF.emitProjectBoxCall(box, metadata),
                                     type: PointerType(pointee: ti.llvmType))
    return ti.address(for: address)
  }
}

// MARK: Function Type Info

/// Provides type information for a function or function reference.
///
/// FIXME: We currently assume that all functions are "thick" - that is, they
/// consist of a function pointer and an environment pointer.  In many cases,
/// we can optimize this by providing "thin" single-scalar type information '
/// instead.
final class FunctionTypeInfo: LoadableTypeInfo {
  let llvmType: IRType
  let fixedSize: Size
  let fixedAlignment: Alignment
  let formalType: Seismography.FunctionType

  init(_ IGM: IRGenModule, _ formalType: Seismography.FunctionType,
       _ storageType: IRType, _ size: Size, _ align: Alignment) {
    self.formalType = formalType
    self.llvmType = storageType
    self.fixedSize = size
    self.fixedAlignment = align
  }

  var isKnownEmpty: Bool {
    return self.fixedSize == .zero
  }

  func explosionSize() -> Int {
    return 2
  }

  func initialize(_ IGF: IRGenFunction, _ from: Explosion, _ addr: Address) {
    // Store the function pointer.
    let fnAddr = self.projectFunction(IGF, addr)
    IGF.B.buildStore(from.claimSingle(),
                     to: fnAddr.address, alignment: fnAddr.alignment)

    // Store the environment pointer.
    let envAddr = self.projectEnvironment(IGF, addr)
    let context = from.claimSingle()
    IGF.B.buildStore(context,
                     to: envAddr.address, alignment: envAddr.alignment)
  }

  func loadAsCopy(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    let fnAddr = self.projectFunction(IGF, addr)
    let first = IGF.B.createLoad(fnAddr)
    explosion.append(first)

    let envAddr = self.projectEnvironment(IGF, addr)
    let second = IGF.B.createLoad(envAddr)
    explosion.append(second)
  }

  func loadAsTake(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    // Load the function.
    let fnAddr = self.projectFunction(IGF, addr)
    explosion.append(IGF.B.createLoad(fnAddr))

    // Load the environment pointer.
    let dataAddr = self.projectEnvironment(IGF, addr)
    explosion.append(IGF.B.createLoad(dataAddr))
  }

  func copy(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    src.transfer(into: dest, 1)
    let data = src.claimSingle()
    dest.append(data)
  }

  func consume(_ IGF: IRGenFunction, _ explosion: Explosion) {
    _ = explosion.claimSingle()
    _ = explosion.claimSingle()
    fatalError("Release the data pointer box!")
  }

  func reexplode(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    let size = self.explosionSize()
    src.transfer(into: dest, size)
  }

  func packIntoPayload(_ IGF: IRGenFunction, _ payload: Payload,
                       _ src: Explosion, _ offset: Size) {
    payload.insertValue(IGF, src.claimSingle(), offset)
    payload.insertValue(IGF, src.claimSingle(),
                        offset + IGF.IGM.getPointerSize())
  }

  func unpackFromPayload(_ IGF: IRGenFunction, _ payload: Payload,
                         _ destination: Explosion, _ offset: Size) {
    fatalError("Unimplemented")
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) {
    _ = IGF.B.createLoad(self.projectEnvironment(IGF, addr))
    fatalError("Release the data pointer box!")
  }

  func assign(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Address) {
    let firstAddr = projectFunction(IGF, dest)
    IGF.B.buildStore(src.claimSingle(), to: firstAddr.address)

    let secondAddr = projectEnvironment(IGF, dest)
    IGF.B.buildStore(src.claimSingle(), to: secondAddr.address)
  }

  func assignWithCopy(_ IGF: IRGenFunction, _ dest: Address,
                      _ src: Address, _ T: GIRType) {
    let temp = Explosion()
    self.loadAsCopy(IGF, src, temp)
    self.assign(IGF, temp, dest)
  }

  func buildAggregateLowering(_ IGM: IRGenModule,
                              _ builder: AggregateLowering.Builder,
                              _ offset: Size) {
    let size = IGM.dataLayout.storeSize(of: self.llvmType) as Size
    builder.append(.concrete(type: self.llvmType, begin: offset, end: size))
  }

  func buildExplosionSchema(_ schema: Explosion.Schema.Builder) {
    schema.append(.scalar(self.llvmType))
  }


  private func projectFunction(_ IGF: IRGenFunction,
                               _ address: Address) -> Address {
    return IGF.B.createStructGEP(address, 0, Size.zero, ".fn")
  }

  private func projectEnvironment(_ IGF: IRGenFunction,
                                  _ address: Address) -> Address {
    return IGF.B.createStructGEP(address, 1, IGF.IGM.getPointerSize(), ".data")
  }
}

// MARK: Generic Type Info

/// Provides type information for a runtime-sized generic value.
final class OpaqueArchetypeTypeInfo: WitnessSizedTypeInfo {
  let llvmType: IRType
  let alignment: Alignment

  init(_ storageType: IRType) {
    self.llvmType = storageType
    self.alignment = Alignment.one
  }
}

// MARK: Tuple Type Info

protocol TupleTypeInfo: TypeInfo {
  var fields: [RecordField] { get }
}

extension TupleTypeInfo {
  func projectElementAddress(
    _ IGF: IRGenFunction, _ tuple: Address, _ type: GIRType, _ fieldNo: Int
  ) -> Address {
    let field = self.fields[fieldNo]
    guard !field.isEmpty else {
      return field.layout.typeInfo.undefAddress()
    }

    let offsets = (self as? DynamicOffsetable)?.dynamicOffsets(IGF, type)
    return field.projectAddress(IGF, tuple, offsets)
  }
}
