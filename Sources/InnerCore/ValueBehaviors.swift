/// IRValueBehaviors.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import LLVM
import Seismography

/// A type that provides information to extend an aggregate lowering schema for
/// a value.
///
/// Aggregate lowering is the first step in the physical lowering of an abstract
/// value to an ABI-relevant runtime value.  The aggregate lowering algorithm
/// is a facility to automatically lay out a naive description of a sequence of
/// byte ranges provided to a builder object.  This description is then
/// transformed and legalized into a valid layout for the given type, and used
/// to guide the ABI conventions for the value.
///
/// A size range may either be associated with a concrete `IRType`, in which
/// case the size of the range must match the size of the type, or an
/// opaque size range.
protocol Aggregable {
  /// Append a proposed storage range describing a possible runtime layout
  /// for this value.
  ///
  /// - Parameters:
  ///   - IGM: The IR Builder for the current module.
  ///   - builder: The aggregate lowering builder.
  ///   - offset: The next available offset.  For aggregate structures, this
  ///     value should be adjusted forward for each member.
  func buildAggregateLowering(_ IGM: IRGenModule,
                              _ builder: AggregateLowering.Builder,
                              _ offset: Size)
}

/// A type that provides a custom assign-with-copy operation.
protocol Assignable {
  /// Copy a value out of an object and into another, destroying the old value
  /// in the destination.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - destination: The address of the destination value.
  ///   - source: The addreses of the source value.
  ///   - type: The type of the value at the source.
  func assignWithCopy(_ IGF: IRGenFunction,
                      _ destination: Address, _ source: Address,
                      _ type: GIRType)
}

/// A type that provides a custom destruction mechanism for a value.
protocol Destroyable {
  /// A custom destruction function for a value at the given address.  The type
  /// of the value is provided to aid dynamic deallocation routines.
  ///
  /// Trivial values and POD values of trivial values should override this
  /// function and provide a no-op implementation.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - address: The address of a value to destroy.
  ///   - type: The type of the value to destroy.
  func destroy(_ IGF: IRGenFunction, _ address: Address, _ type: GIRType)
}

/// A type that provides information to extend an explosion schema for a value.
///
/// An `Explodable` type must be able to append a profile of its structure to
/// the given builder, or delegate the responsibility to its fields.
protocol Explodable {
  /// Append an explosion schema describing the structure of this value to the
  /// given builder.
  ///
  /// - Parameter builder: The explosion schema builder.
  func buildExplosionSchema(_ builder: Explosion.Schema.Builder)
}

/// A type that has a fully-exposed concrete representation.  Because its
/// representation is explicitly known, directly loading and storing this value
/// into member is always a legal operation.
protocol Loadable {
  /// Computes and returns the size of an explosion for this value.
  ///
  /// - NOTE: This operation should avoid recomputing the explosion schema.
  func explosionSize() -> Int

  /// Initialize a given address with the values from an explosion.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - source: The explosion containing the source values.
  ///   - address: The address of the value to initialize.
  func initialize(_ IGF: IRGenFunction, _ source: Explosion, _ address: Address)
  /// Assign a set of exploded values into an address.  The values are
  /// consumed out of the explosion.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - source: The explosion containing the source values.
  ///   - destination: The address of the value to initialize.
  func assign(_ IGF: IRGenFunction, _ source: Explosion, _ destination: Address)

  /// Shift values from the source explosion to the destination explosion as
  /// if by copy-initialization.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - source: The explosion containing the source values.
  ///   - destination: The destination explosion.
  func copy(_ IGF: IRGenFunction, _ source: Explosion, _ destination: Explosion)
  /// Release the values contained in an explosion.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - explosion: The explosion containing the values to consume.
  func consume(_ IGF: IRGenFunction, _ explosion: Explosion)

  /// Load an values from an address into an explosion value as if by
  /// copy-initialization.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - source: The address containing the value(s) to load.
  ///   - destination: The destination explosion.
  func loadAsCopy(_ IGF: IRGenFunction,
                  _ source: Address, _ destination: Explosion)
  /// Load an values from an address into an explosion value as if by
  /// take-initialization.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - source: The address containing the value(s) to load.
  ///   - destination: The destination explosion.
  func loadAsTake(_ IGF: IRGenFunction,
                  _ source: Address, _ destination: Explosion)

  /// Pack the source explosion into a data type payload destination.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - payload: The payload into which the value will be packed.
  ///   - source: The explosion containing the set of values to store.
  ///   - offset: The offset at which to pack the value.
  func packIntoPayload(_ IGF: IRGenFunction,
                       _ payload: Payload, _ source: Explosion, _ offset: Size)
  /// Unpack values from a data type payload into a destination explosion.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - payload: The payload from which the value will be unpacked.
  ///   - destination: The destination explosion.
  ///   - offset: The offset at which to unpack the value.
  func unpackFromPayload(_ IGF: IRGenFunction,
                         _ payload: Payload, _ destination: Explosion,
                         _ offset: Size)

  /// Consume a bunch of values which have exploded at one explosion
  /// level and produce them at another.
  ///
  /// Essentially, this is like take-initializing the new explosion.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - source: The source explosion.
  ///   - destination: The destination explosion.
  func reexplode(_ IGF: IRGenFunction,
                 _ source: Explosion, _ destination: Explosion)
}

/// A type that provides custom stack allocation and deallocation routines.
protocol StackAllocatable {
  /// Allocate a value of this type on the stack.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - type: The type of the value to allocate.
  /// - Returns: The stack address of the allocation.
  func allocateStack(_ IGF: IRGenFunction, _ type: GIRType) -> StackAddress

  /// Deallocate a value of this type that is resident on the stack.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - address: The stack address of the value to deallocate.
  ///   - type: The type of the value to deallocate.
  func deallocateStack(_ IGF: IRGenFunction,
                       _ address: StackAddress, _ type: GIRType)
}

/// A type that provides a way to query whether it is a "plain old data" value.
///
/// A POD type does not require further action to copy, move, or destroy it or
/// its fields.
protocol PODable {
  /// Returns `true` if the described type is a "plain old data" type, `false`
  /// otherwise.
  var isPOD: Bool { get }
}

extension PODable {
  var isPOD: Bool {
    return false
  }
}

/// A type that provides access to an underlying data type strategy describing
/// its concrete implementation.
///
/// `Strategizable` types generally defer the implementation of their protocol
/// requirements to their underlying strategy.
protocol Strategizable {
  var strategy: DataTypeStrategy { get }
}

extension Strategizable {
  func buildExplosionSchema(_ schema: Explosion.Schema.Builder) {
    self.strategy.buildExplosionSchema(schema)
  }
}

/// A type that provides custom retain and release functions for one or more
/// scalar values.  The type should essentially be thought of as a single
/// scalar value.
protocol Scalarizable {
  /// Compute whether the underlying type is a "Plain Old Data" type.
  ///
  /// POD types have trivial representations and require no effort to copy,
  /// move, retain, release, or destroy.  Returning `true` from the accessor
  /// opts-in to those optimizations in the default implementations of many
  /// scalar `TypeInfo` requirements.
  static var isPOD: Bool { get }

  /// Emit an operation to "retain" a given value.
  ///
  /// For non-reference-typed scalar values, this operation is a no-op.  For
  /// scalar values that are references, this may cause a reference count
  /// increase.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - value: The value to retain.
  func emitScalarRetain(_ IGF: IRGenFunction, _ value: IRValue)

  /// Emit an operation to "release" a given value.
  ///
  /// For non-reference-typed scalar values, this operation is a no-op.  For
  /// scalar values that are references, this may cause a reference count
  /// decrease.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - value: The value to release.
  func emitScalarRelease(_ IGF: IRGenFunction, _ value: IRValue)
}

extension Scalarizable {
  var isPOD: Bool {
    return type(of: self).isPOD
  }
}

/// A refinement of the `Scalarizable` for values with
/// a single scalar as their underlying representation.
protocol SingleScalarizable: Scalarizable { }

extension SingleScalarizable {
  func assign(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Address) {
    // Grab the old value if we need to.
    var oldValue: IRValue?
    if !type(of: self).isPOD {
      oldValue = IGF.B.createLoad(dest, name: "oldValue")
    }

    // Store.
    let newValue = src.claimSingle()
    IGF.B.buildStore(newValue, to: dest.address)

    // Release the old value if we need to.
    if let valToRelease = oldValue {
      self.emitScalarRelease(IGF, valToRelease)
    }
  }

  func emitScalarRetain(_ IGF: IRGenFunction, _ value: IRValue) {
    guard !type(of: self).isPOD else {
      return
    }
    IGF.GR.emitRetain(value)
  }

  func emitScalarRelease(_ IGF: IRGenFunction, _ value: IRValue) {
    guard !type(of: self).isPOD else {
      return
    }
    IGF.GR.emitRelease(value)
  }
}

protocol FixedHeapLayout {
  var layout: RecordLayout { get }
}

extension FixedHeapLayout {
  func allocate(_ IGF: IRGenFunction, _ boxedType: GIRType) -> OwnedAddress {
    // Allocate a new object using the layout.
    let boxDescriptor = IGF.IGM.addressOfBoxDescriptor(for: boxedType)
    let allocation = IGF.GR.emitUnmanagedAlloc(self.layout, boxDescriptor)
    let rawAddr = project(IGF, allocation, boxedType)
    return OwnedAddress(rawAddr, allocation)
  }

  func deallocate(_ IGF: IRGenFunction, _ box: IRValue, _ boxedType: GIRType) {
    let size = layout.emitSize(IGF.IGM)
    let alignMask = layout.emitAlignMask(IGF.IGM)

    IGF.GR.emitDeallocUninitializedObject(box, size, alignMask)
  }

  func project(_ IGF: IRGenFunction,
               _ box: IRValue, _ boxedType: GIRType) -> Address {
    let asBox = layout.emitCastTo(IGF, box, "")
    let rawAddr = layout.fieldLayouts[0].project(IGF, asBox, "", nil)
    let ti = IGF.getTypeInfo(boxedType)
    let ptrTy = PointerType(pointee: ti.llvmType)
    return IGF.B.createPointerBitCast(of: rawAddr, to: ptrTy)
  }
}

protocol DynamicOffsets {
  func offsetForIndex(_ IGF: IRGenFunction, _ index: Int) -> IRValue
}

protocol DynamicOffsetable {
  func dynamicOffsets(_ IGF: IRGenFunction, _ T: GIRType) -> DynamicOffsets?
}
