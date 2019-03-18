/// IRGenStrategy.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import LLVM
import Seismography
import OuterCore
import Mantle

extension IRGenModule {
  /// Computes the strategy to implement a particular
  ///
  /// - Parameters:
  ///   - TC: A type converter.
  ///   - type: The GIR data type to strategize about.
  ///   - llvmType: The LLVM type declaration for this layout.
  /// - Returns: The strategy used to implement values of this data type.
  func strategize(_ TC: TypeConverter, _ type: DataType,
                  _ llvmType: StructType) -> DataTypeStrategy {
    let numElements = type.constructors.count
    var tik = DataTypeLayoutPlanner.TypeInfoKind.loadable

    if let strat = self.getAsNatural(TC.IGM, type, llvmType) {
      return strat
    }

    var elementsWithPayload = [DataTypeLayoutPlanner.Element]()
    var elementsWithNoPayload = [DataTypeLayoutPlanner.Element]()

    for constr in type.constructors {
      guard let origArgType = constr.payload else {
        elementsWithNoPayload.append(.dynamic(constr.name))
        continue
      }

      if origArgType is BoxType {
        let managedTI = ManagedObjectTypeInfo(self.refCountedPtrTy,
                                              self.getPointerSize(),
                                              self.getPointerAlignment())
        elementsWithPayload.append(.fixed(constr.name, managedTI))
        continue
      }

      if let constrTI = TC.getCompleteTypeInfo(origArgType) as? FixedTypeInfo {
        elementsWithPayload.append(.fixed(constr.name, constrTI))
        if !(constrTI is LoadableTypeInfo) && tik == .loadable {
          tik = .fixed
        }
      } else {
        elementsWithPayload.append(.dynamic(constr.name))
        tik = .dynamic
      }
    }

    let planner = DataTypeLayoutPlanner(IGM: TC.IGM,
                                        girType: type,
                                        storageType: llvmType,
                                        typeInfoKind: tik,
                                        withPayload: elementsWithPayload,
                                        withoutPayload: elementsWithNoPayload)

    if numElements <= 1 {
      return NewTypeDataTypeStrategy(planner)
    }

    if elementsWithPayload.count > 1 {
      // return MultiPayloadDataTypeStrategy(planner)
      fatalError("Unimplemented!")
    }

    if elementsWithPayload.count == 1 {
      return SinglePayloadDataTypeStrategy(planner)
    }

    if elementsWithNoPayload.count <= 2 {
      return SingleBitDataTypeStrategy(planner)
    }

    assert(elementsWithPayload.isEmpty)
    return NoPayloadDataTypeStrategy(planner)
  }

  private func getAsNatural(_ IGM: IRGenModule,
                            _ type: DataType, _ llvmType: StructType
  ) -> DataTypeStrategy? {
    guard type.constructors.count == 2 else {
      return nil
    }

    let oneCon = type.constructors[0]
    let twoCon = type.constructors[1]

    guard (oneCon.payload == nil) != (twoCon.payload == nil) else {
      return nil
    }

    let planner = DataTypeLayoutPlanner(IGM: IGM,
                                        girType: type,
                                        storageType: llvmType,
                                        typeInfoKind: .fixed,
                                        withPayload: [],
                                        withoutPayload: [])
    if let succ = oneCon.payload as? TupleType {
      guard succ.elements.count == 1 else {
        return nil
      }

      guard let dataSucc = succ.elements[0] as? DataType else {
        return nil
      }

      guard dataSucc === type else {
        return nil
      }
      return NaturalDataTypeStrategy(twoCon.name, planner)
    } else if let succ = twoCon.payload as? TupleType {
      guard succ.elements.count == 1 else {
        return nil
      }

      guard let dataSucc = succ.elements[0] as? DataType else {
        return nil
      }

      guard dataSucc === type else {
        return nil
      }
      return NaturalDataTypeStrategy(oneCon.name, planner)
    } else {
      return nil
    }
  }
}

/// Implements a data type strategy for a type with exactly one case
/// which can optionally carry a payload value.
///
/// The precise layout of the value can take one of two forms:
///
/// - Without Payload:
///   - Layout: empty.
///   - To construct: No-op.
///   - To discriminate: No-op.
///   - To destruct: No-op.
///
/// - With Payload:
///   - Layout: Payload's layout.
///   - To construct: Construct the payload by re-explosion.
///   - To discriminate: No-op.
///   - To destruct: Extract the payload value by re-explosion.
///
/// In either case, there is no value to discriminate, and all `switch_constr`
/// instructions are resolved to direct branches.
final class NewTypeDataTypeStrategy: DataTypeStrategy {
  let planner: DataTypeLayoutPlanner

  init(_ planner: DataTypeLayoutPlanner) {
    self.planner = planner
    self.planner.fulfill { (planner) -> TypeInfo in
      guard !planner.payloadElements.isEmpty else {
        planner.llvmType.setBody([], isPacked: true)
        return LoadableDataTypeTypeInfo(self, planner.llvmType, .zero, .one)
      }

      guard
        case let .some(.fixed(_, eltTI)) = planner.payloadElements.first
      else {
        fatalError()
      }

      switch planner.optimalTypeInfoKind {
      case .dynamic:
        let alignment = eltTI.alignment
        planner.llvmType.setBody([], isPacked: true)
        return DynamicDataTypeTypeInfo(self, planner.llvmType, alignment)
      case .loadable:
        let alignment = eltTI.alignment
        planner.llvmType.setBody([ eltTI.llvmType ], isPacked: true)
        return LoadableDataTypeTypeInfo(self, planner.llvmType,
                                        eltTI.fixedSize, alignment)
      case .fixed:
        let alignment = eltTI.alignment
        planner.llvmType.setBody([ eltTI.llvmType ], isPacked: true)
        return FixedDataTypeTypeInfo(self, planner.llvmType,
                                     eltTI.fixedSize, alignment)
      }
    }
  }

  private func getSingleton() -> TypeInfo? {
    switch self.planner.payloadElements[0] {
    case .dynamic(_):
      return nil
    case let .fixed(_, ti):
      return ti
    }
  }

  private func getLoadableSingleton() -> LoadableTypeInfo? {
    switch self.planner.payloadElements[0] {
    case .dynamic(_):
      return nil
    case let .fixed(_, ti):
      return ti as? LoadableTypeInfo
    }
  }


  func initialize(_ IGF: IRGenFunction, _ from: Explosion, _ addr: Address) {
    if let singleton = getLoadableSingleton() {
      let ptrTy = PointerType(pointee: singleton.llvmType)
      let ptr = IGF.B.createPointerBitCast(of: addr, to: ptrTy)
      singleton.initialize(IGF, from, ptr)
    }
  }

  func reexplode(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    getLoadableSingleton()?.reexplode(IGF, src, dest)
  }

  func loadAsTake(_ IGF: IRGenFunction, _ addr: Address, _ out: Explosion) {
    if let singleton = getLoadableSingleton() {
      let ptrTy = PointerType(pointee: singleton.llvmType)
      let ptr = IGF.B.createPointerBitCast(of: addr, to: ptrTy)
      singleton.loadAsTake(IGF, ptr, out)
    }
  }

  func loadAsCopy(_ IGF: IRGenFunction, _ addr: Address, _ out: Explosion) {
    if let singleton = getLoadableSingleton() {
      let ptrTy = PointerType(pointee: singleton.llvmType)
      let ptr = IGF.B.createPointerBitCast(of: addr, to: ptrTy)
      singleton.loadAsCopy(IGF, ptr, out)
    }
  }

  func emitSwitch(_ IGF: IRGenFunction, _ value: Explosion,
                  _ dests: [(String, BasicBlock)], _ def: BasicBlock?) {
    _ = value.claimSingle()
    guard let dest = dests.count == 1 ? dests[0].1 : def else {
      fatalError()
    }
    IGF.B.buildBr(dest)
  }


  func emitDataInjection(_ IGF: IRGenFunction, _ : String,
                         _ data: Explosion, _ out: Explosion) {
    getLoadableSingleton()?.reexplode(IGF, data, out)
  }

  func emitDataProjection(_ IGF: IRGenFunction, _ : String,
                          _ value: Explosion, _ projected: Explosion) {
    getLoadableSingleton()?.reexplode(IGF, value, projected)
  }

  func buildExplosionSchema(_ builder: Explosion.Schema.Builder) {
    guard let singleton = getSingleton() else {
      return
    }

    if self.planner.optimalTypeInfoKind == .loadable {
      return singleton.buildExplosionSchema(builder)
    }

    // Otherwise, use an indirect aggregate schema with our storage type.
    builder.append(.aggregate(singleton.llvmType, singleton.alignment))
  }

  func buildAggregateLowering(_ IGM: IRGenModule,
                              _ builder: AggregateLowering.Builder,
                              _ offset: Size) {
    getLoadableSingleton()?.buildAggregateLowering(IGM, builder, offset)
  }

  func copy(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    getLoadableSingleton()?.copy(IGF, src, dest)
  }

  func explosionSize() -> Int {
    return getLoadableSingleton()?.explosionSize() ?? 0
  }

  func consume(_ IGF: IRGenFunction, _ explosion: Explosion) {
    getLoadableSingleton()?.consume(IGF, explosion)
  }

  func packIntoPayload(_ IGF: IRGenFunction, _ payload: Payload,
                       _ source: Explosion, _ offset: Size) {
    getLoadableSingleton()?.packIntoPayload(IGF, payload, source, offset)
  }

  func unpackFromPayload(_ IGF: IRGenFunction, _ payload: Payload,
                         _ destination: Explosion, _ offset: Size) {
    getLoadableSingleton()?.unpackFromPayload(IGF, payload, destination, offset)
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) {
    if getLoadableSingleton() != nil {
      IGF.GR.emitDestroyCall(type, addr)
    }
  }

  func assign(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Address) {
    getLoadableSingleton()?.assign(IGF, src, dest)
  }

  func assignWithCopy(_ IGF: IRGenFunction, _ dest: Address,
                      _ src: Address, _ type: GIRType) {
    if getLoadableSingleton() != nil {
      IGF.GR.emitAssignWithCopyCall(type, dest, src)
    }
  }
}

/// Implements a data type strategy for a type with exactly two cases with no
/// payload.  The underlying LLVM type is an `i1`, and discrimination is done
/// by conditional branch.
final class SingleBitDataTypeStrategy: NoPayloadStrategy {
  let planner: DataTypeLayoutPlanner

  init(_ planner: DataTypeLayoutPlanner) {
    self.planner = planner
    self.planner.fulfill { (planner) -> TypeInfo in
      if planner.noPayloadElements.count == 2 {
        planner.llvmType.setBody([ IntType.int1 ], isPacked: true)
      } else {
        planner.llvmType.setBody([], isPacked: true)
      }
      let size = Size(planner.noPayloadElements.count == 2 ? 1 : 0)
      return LoadableDataTypeTypeInfo(self, planner.llvmType, size, .one)
    }
  }

  func buildExplosionSchema(_ schema: Explosion.Schema.Builder) {
    guard self.planner.noPayloadElements.count == 2 else {
      return
    }

    schema.append(.scalar(IntType.int1))
  }

  func buildAggregateLowering(_ IGM: IRGenModule,
                              _ builder: AggregateLowering.Builder,
                              _ offset: Size) {
    guard self.planner.noPayloadElements.count == 2 else {
      return
    }

    builder.append(.opaque(begin: offset, end: offset + Size(1)))
  }

  func emitDataInjection(_ IGF: IRGenFunction, _ target: String,
                         _ data: Explosion, _ out: Explosion) {
    guard self.planner.noPayloadElements.count == 2 else {
      return
    }

    out.append(self.planner.noPayloadElements.firstIndex(where: {
      $0.selector == target
    }) ?? 0)
  }

  func initialize(_ IGF: IRGenFunction, _ from: Explosion, _ addr: Address) {
    let addr = IGF.B.createStructGEP(addr, 0, .zero, "")
    IGF.B.buildStore(from.claimSingle(), to: addr.address)
  }

  func copy(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    dest.append(src.claimSingle())
  }

  func reexplode(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    src.transfer(into: dest, self.explosionSize())
  }

  func loadAsCopy(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    let addr = IGF.B.createStructGEP(addr, 0, .zero, "")
    explosion.append(IGF.B.buildLoad(addr.address))
  }

  func loadAsTake(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    let addr = IGF.B.createStructGEP(addr, 0, .zero, "")
    explosion.append(IGF.B.buildLoad(addr.address))
  }

  func emitDataProjection(_ IGF: IRGenFunction, _ : String,
                          _ value: Explosion, _ projected: Explosion) {
    _ = value.claim(next: self.explosionSize())
  }

  func consume(_ IGF: IRGenFunction, _ explosion: Explosion) {
    _ = explosion.claimSingle()
  }

  func packIntoPayload(_ IGF: IRGenFunction, _ payload: Payload,
                       _ source: Explosion, _ offset: Size) {
    payload.insertValue(IGF, source.claimSingle(), offset)
  }

  func unpackFromPayload(_ IGF: IRGenFunction, _ payload: Payload,
                         _ destination: Explosion, _ offset: Size) {
    destination.append(payload.extractValue(IGF,
                                            self.typeInfo().llvmType, offset))
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) { }

  func assign(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Address) {
    let newValue = src.claimSingle()
    IGF.B.buildStore(newValue, to: dest.address)
  }

  func assignWithCopy(_ IGF: IRGenFunction,
                      _ dest: Address, _ src: Address, _ : GIRType) {
    let temp = Explosion()
    self.loadAsTake(IGF, src, temp)
    self.initialize(IGF, temp, dest)
  }
}

/// Implements a data type strategy for a type where no case has a payload
/// value.  The underlying LLVM type is the least power-of-two-width integral
/// type needed to store the discriminator.
final class NoPayloadDataTypeStrategy: NoPayloadStrategy {
  let planner: DataTypeLayoutPlanner

  init(_ planner: DataTypeLayoutPlanner) {
    self.planner = planner
    self.planner.fulfill { (planner) -> TypeInfo in
      // Since there are no payloads, we need just enough bits to hold a
      // discriminator.
      let usedTagBits = log2(UInt64(planner.noPayloadElements.count - 1)) + 1
      let (tagSize, tagTy) = computeTagLayout(planner.IGM, usedTagBits)
      planner.llvmType.setBody([ tagTy ], isPacked: true)

      let alignment = Alignment(UInt32(tagSize.rawValue))
      return LoadableDataTypeTypeInfo(self, planner.llvmType,
                                      tagSize, alignment)
    }
  }

  func buildExplosionSchema(_ schema: Explosion.Schema.Builder) {
    schema.append(.scalar(getDiscriminatorType()))
  }

  func fixedSize() -> Size {
    return Size(UInt64(self.getDiscriminatorType().width + 7) / 8)
  }

  func buildAggregateLowering(_ IGM: IRGenModule,
                              _ builder: AggregateLowering.Builder,
                              _ offset: Size) {
    builder.append(.opaque(begin: offset, end: offset + self.fixedSize()))
  }

  func emitDataInjection(_ IGF: IRGenFunction, _ selector: String,
                         _ data: Explosion, _ out: Explosion) {
    out.append(discriminatorIndex(for: selector))
  }

  func reexplode(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    src.transfer(into: dest, 1)
  }

  func initialize(_ IGF: IRGenFunction, _ src: Explosion, _ addr: Address) {
    IGF.B.buildStore(src.claimSingle(), to: addr.address)
  }

  func loadAsTake(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    explosion.append(IGF.B.buildLoad(addr.address))
  }

  func loadAsCopy(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    let value = IGF.B.buildLoad(addr.address)
    self.emitScalarRelease(IGF, value)
    explosion.append(value)
  }

  func copy(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    dest.append(src.claimSingle())
  }

  func emitDataProjection(_ IGF: IRGenFunction, _ : String,
                          _ value: Explosion, _ projected: Explosion) {
    _ = value.claim(next: explosionSize())
  }

  func consume(_ IGF: IRGenFunction, _ explosion: Explosion) {
    _ = explosion.claimSingle()
  }

  func packIntoPayload(_ IGF: IRGenFunction, _ payload: Payload,
                       _ source: Explosion, _ offset: Size) {
    payload.insertValue(IGF, source.claimSingle(), offset)
  }

  func unpackFromPayload(_ IGF: IRGenFunction, _ payload: Payload,
                         _ destination: Explosion, _ offset: Size) {
    let value = payload.extractValue(IGF, self.getDiscriminatorType(), offset)
    destination.append(value)
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) { }

  func assignWithCopy(_ IGF: IRGenFunction,
                      _ dest: Address, _ source: Address, _ : GIRType) {
    let addr = IGF.B.createStructGEP(source, 0, .zero, "")
    let value = IGF.B.buildLoad(addr.address)
    IGF.B.buildStore(value, to: dest.address)
  }
}

/// Implements a strategy for a datatype where exactly one case contains a
/// payload value, and all other cases do not.
///
/// The resulting layout depends mostly on the layout of that payload.  In the
/// simple case, we know nothing about the payload's layout and so must
/// manipulate these values indirectly.  In the case where we know the layout
/// of the payload, we lay the bits out as follows:
///
///     |-8-bits-|-8-bits-|-8-bits-|  ....  |-8-bits-|-8-bits-|-8-bits-|  ....
///     •----------------------------------------------------------------------
///     |        |        |        |        |        |        |        |
///     |        |        |        |        |        |        |        |
///     |     Payload Layout       |  ....  |     Discriminator Bits   |  ....
///     |        |        |        |        |        |        |        |
///     |        |        |        |        |        |        |        |
///     •----------------------------------------------------------------------
///
/// In the future, we will attempt to compute the spare bits available in the
/// layout of the payload and use the unused bitpatterns to reduce the size of
/// the discriminator bit region.
///
/// The payload and discriminator regions are laid out as packed multiples of
/// 8-bit arrays rather than as arbitrary-precision integers to avoid computing
/// bizarre integral types as these can cause FastISel to have some indigestion.
final class SinglePayloadDataTypeStrategy: PayloadStrategy {
  let planner: DataTypeLayoutPlanner

  let payloadSchema: Payload.Schema
  let payloadElementCount: Int

  init(_ planner: DataTypeLayoutPlanner) {
    self.planner = planner

    var payloadBitCount = 0
    switch planner.payloadElements[0] {
    case let .fixed(_, fixedTI):
      self.payloadSchema = .bits(fixedTI.fixedSize.valueInBits())
      var elementCount = 0
      self.payloadSchema.forEachType(planner.IGM) { t in
        elementCount += 1
        payloadBitCount += planner.IGM.dataLayout.sizeOfTypeInBits(t)
      }
      self.payloadElementCount = elementCount
    default:
      self.payloadSchema = .dynamic
      self.payloadElementCount = 0
      payloadBitCount = -1
    }

    let tagLayout = computeTagLayout(planner.IGM,
                                     UInt64(planner.noPayloadElements.count))
    let numTagBits = Int(tagLayout.0.rawValue)
    switch self.planner.optimalTypeInfoKind {
    case .fixed:
      self.planner.fulfill { (planner) -> TypeInfo in
        guard case let .fixed(_, payloadTI) = planner.payloadElements[0] else {
          fatalError()
        }
        assert(payloadBitCount > 0)
        planner.llvmType.setBody([
          ArrayType(elementType: IntType.int8, count: (payloadBitCount+7)/8),
          ArrayType(elementType: IntType.int8, count: numTagBits),
        ], isPacked: true)

        return FixedDataTypeTypeInfo(self, planner.llvmType,
                                    payloadTI.fixedSize, payloadTI.alignment)
      }
    case .loadable:
      self.planner.fulfill { (planner) -> TypeInfo in
        guard case let .fixed(_, payloadTI) = planner.payloadElements[0] else {
          fatalError()
        }
        assert(payloadBitCount > 0)
        planner.llvmType.setBody([
          ArrayType(elementType: IntType.int8, count: (payloadBitCount+7)/8),
          ArrayType(elementType: IntType.int8, count: numTagBits),
        ], isPacked: true)

        return LoadableDataTypeTypeInfo(self, planner.llvmType,
                                        payloadTI.fixedSize,
                                        payloadTI.alignment)
      }
    case .dynamic:
      self.planner.fulfill { (planner) -> TypeInfo in
        // The body is runtime-dependent, so we can't put anything useful here
        // statically.
        planner.llvmType.setBody([], isPacked: true)

        guard case let .fixed(_, ti) = planner.payloadElements[0] else {
          fatalError()
        }
        return DynamicDataTypeTypeInfo(self, planner.llvmType, ti.alignment)
      }
    }
  }

  func emitSwitch(_ IGF: IRGenFunction, _ value: Explosion,
                  _ dests: [(String, BasicBlock)], _ def: BasicBlock?) {
    fatalError("Unimplemented")
  }

  func emitDataInjection(_ IGF: IRGenFunction, _ target: String,
                         _ params: Explosion, _ out: Explosion) {
    guard target != self.planner.payloadElements[0].selector else {
      // Compute an empty bitpattern and pack the given value into it.
      let payload = Payload.zero(IGF.IGM, self.payloadSchema)
      getLoadablePayloadTypeInfo().packIntoPayload(IGF, payload, params, 0)
      payload.explode(IGF.IGM, out)
      return
    }

    /// Compute the bitpattern for the discriminator and pack it as our
    /// payload value.
    let tagIdx = self.indexOf(selector: target)
    let bitWidth = getFixedPayloadTypeInfo().fixedSize.valueInBits()
    let pattern = APInt(width: Int(bitWidth), value: tagIdx)
    let payload = Payload.fromBitPattern(IGF.IGM, pattern, self.payloadSchema)
    payload.explode(IGF.IGM, out)
  }

  func initialize(_ IGF: IRGenFunction, _ from: Explosion, _ addr: Address) {
    let payload = Payload.fromExplosion(planner.IGM, from, self.payloadSchema)
    payload.store(IGF, addr)
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) {
    let ptrTy = PointerType(pointee: IGF.IGM.refCountedPtrTy)
    let addr = IGF.B.createPointerBitCast(of: addr, to: ptrTy)
    let ptr = IGF.B.buildLoad(addr.address)
    IGF.GR.emitRelease(ptr)
  }

  func consume(_ IGF: IRGenFunction, _ explosion: Explosion) {
    let val = explosion.claimSingle()
    let ptr = IGF.B.createBitOrPointerCast(val, to: IGF.IGM.refCountedPtrTy)
    IGF.GR.emitRelease(ptr)
  }

  func loadAsTake(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    let payload = Payload.load(IGF, addr, self.payloadSchema)
    payload.explode(IGF.IGM, explosion)
  }

  func emitDataProjection(_ IGF: IRGenFunction, _ selector: String,
                          _ value: Explosion, _ projected: Explosion) {
    guard selector == self.planner.payloadElements[0].selector else {
      value.markClaimed(self.explosionSize())
      return
    }

    let payload = Payload.fromExplosion(IGF.IGM, value, self.payloadSchema)
    getLoadablePayloadTypeInfo().unpackFromPayload(IGF, payload, projected, 0)
  }

  func packIntoPayload(_ IGF: IRGenFunction, _ payload: Payload,
                       _ source: Explosion, _ offset: Size) {
    let payload = Payload.fromExplosion(IGF.IGM, source, self.payloadSchema)
    payload.packIntoEnumPayload(IGF, payload, offset)
  }

  func unpackFromPayload(_ IGF: IRGenFunction, _ payload: Payload,
                         _ destination: Explosion, _ offset: Size) {
    let payload = Payload.unpackFromPayload(IGF, payload, offset,
                                            self.payloadSchema)
    payload.explode(IGF.IGM, destination)
  }

  func assignWithCopy(_ IGF: IRGenFunction, _ dest: Address,
                      _ src: Address, _ type: GIRType) {
    IGF.GR.emitAssignWithCopyCall(type, dest, src)
  }
}

final class NaturalDataTypeStrategy: NoPayloadStrategy {
  let planner: DataTypeLayoutPlanner

  let fixedSize: Size
  let fixedAlignment: Alignment
  let zeroName: String

  init(_ zero: String, _ planner: DataTypeLayoutPlanner) {
    self.zeroName = zero
    self.planner = planner
    self.fixedSize =
      Size(bits: UInt64(planner.IGM.dataLayout.intPointerType().width))
    self.fixedAlignment = .one

    self.planner.fulfill { (planner) -> TypeInfo in
      // HACK: Use the platform's int type.  [32/64] bits ought to be enough for
      // anybody...
      let intTy = planner.IGM.dataLayout.intPointerType()
      planner.llvmType.setBody([
        intTy
      ], isPacked: true)

      let tagSize = Size(bits: UInt64(intTy.width))
      let alignment: Alignment = planner.IGM.dataLayout.abiAlignment(of: intTy)
      return LoadableDataTypeTypeInfo(self, planner.llvmType,
                                      tagSize, alignment)
    }
  }

  func scalarType() -> IntType {
    return planner.IGM.dataLayout.intPointerType()
  }

  func discriminatorIndex(for target: String) -> Constant<Signed> {
    return self.scalarType().constant(0)
  }

  func emitDataProjection(_ IGF: IRGenFunction, _ selector: String,
                          _ value: Explosion, _ projected: Explosion) {
    let val = value.claimSingle()
    guard selector != self.zeroName else {
      return
    }
    projected.append(IGF.B.buildSub(val, self.scalarType().constant(1)))
  }

  func emitSwitch(_ IGF: IRGenFunction, _ value: Explosion,
                  _ dests: [(String, BasicBlock)], _ def: BasicBlock?) {
    let discriminator = value.peek()

    let defaultDest = def ?? {
      let defaultDest = IGF.function.appendBasicBlock(named: "")
      let pos = IGF.B.insertBlock!
      IGF.B.positionAtEnd(of: defaultDest)
      IGF.B.buildUnreachable()
      IGF.B.positionAtEnd(of: pos)
      return defaultDest
    }()

    switch dests.count {
    case 0:
      guard def != nil else {
        IGF.B.buildUnreachable()
        return
      }
      IGF.B.buildBr(defaultDest)
    case 1:
      let cmp = IGF.B.buildICmp(discriminator,
                                self.scalarType().zero(), .notEqual)
      IGF.B.buildCondBr(condition: cmp, then: dests[0].1, else: defaultDest)
    case 2 where def == nil:
      let firstDest = dests[0]
      let nextDest = dests[1]
      let caseTag = discriminatorIndex(for: firstDest.0)
      let cmp = IGF.B.buildICmp(discriminator, caseTag, .equal)
      IGF.B.buildCondBr(condition: cmp, then: firstDest.1, else: nextDest.1)
      defaultDest.removeFromParent()
    default:
      let switchInst = IGF.B.buildSwitch(discriminator, else: defaultDest,
                                         caseCount: dests.count)
      for (name, dest) in dests {
        switchInst.addCase(discriminatorIndex(for: name), dest)
      }
    }
  }

  func buildExplosionSchema(_ schema: Explosion.Schema.Builder) {
    schema.append(.scalar(scalarType()))
  }

  func buildAggregateLowering(_ IGM: IRGenModule,
                              _ builder: AggregateLowering.Builder,
                              _ offset: Size) {
    builder.append(.opaque(begin: offset, end: offset + self.fixedSize))
  }

  func emitDataInjection(_ IGF: IRGenFunction, _ : String,
                         _ data: Explosion, _ out: Explosion) {
    if data.count == 0 {
      out.append(self.scalarType().constant(0))
    } else {
      let curValue = data.claimSingle()
      out.append(IGF.B.buildAdd(curValue, self.scalarType().constant(1)))
    }
  }

  func reexplode(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    src.transfer(into: dest, self.explosionSize())
  }

  func initialize(_ IGF: IRGenFunction, _ src: Explosion, _ addr: Address) {
    IGF.B.buildStore(src.claimSingle(), to: addr.address)
  }

  func loadAsTake(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    explosion.append(IGF.B.buildLoad(addr.address))
  }

  func loadAsCopy(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    explosion.append(IGF.B.buildLoad(addr.address))
  }

  func copy(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    let value = src.claimSingle()
    dest.append(value)
  }

  func packIntoPayload(_ IGF: IRGenFunction, _ payload: Payload,
                       _ source: Explosion, _ offset: Size) {
    payload.insertValue(IGF, source.claimSingle(), offset)
  }

  func unpackFromPayload(_ IGF: IRGenFunction, _ payload: Payload,
                         _ destination: Explosion, _ offset: Size) {
    destination.append(payload.extractValue(IGF, self.scalarType(), offset))
  }

  func consume(_ IGF: IRGenFunction, _ explosion: Explosion) { }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) { }

  func assign(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Address) {
    let newValue = src.claimSingle()
    IGF.B.buildStore(newValue, to: dest.address)
  }

  func assignWithCopy(_ IGF: IRGenFunction, _ dest: Address,
                      _ src: Address, _ : GIRType) {
    let temp = Explosion()
    self.loadAsTake(IGF, src, temp)
    self.initialize(IGF, temp, dest)
  }
}

private func isPowerOf2(_ Value: UInt64) -> Bool {
  return (Value != 0) && ((Value & (Value - 1)) == 0)
}

private func nextPowerOfTwo(_ v: UInt64) -> UInt64 {
  var v = v
  v -= 1
  v |= v >> 1
  v |= v >> 2
  v |= v >> 4
  v |= v >> 8
  v |= v >> 16
  v |= v >> 32
  v += 1
  return v
}

private func log2(_ val: UInt64) -> UInt64 {
  return 63 - UInt64(val.leadingZeroBitCount)
}

// Use the best fitting "normal" integer size for the enum. Though LLVM
// theoretically supports integer types of arbitrary bit width, in practice,
// types other than i1 or power-of-two-byte sizes like i8, i16, etc. inhibit
// FastISel and expose backend bugs.
func integerBitSize(for tagBits: UInt64) -> UInt64 {
  // i1 is used to represent bool in C so is fairly well supported.
  if tagBits == 1 {
    return 1
  }
  // Otherwise, round the physical size in bytes up to the next power of two.
  var tagBytes = (tagBits + 7)/8
  if !isPowerOf2(tagBytes) {
    tagBytes = nextPowerOfTwo(tagBytes)
  }
  return Size(tagBytes).valueInBits()
}

private func computeTagLayout(_ IGM: IRGenModule,
                              _ tagBits: UInt64) -> (Size, IntType) {
  let typeBits = integerBitSize(for: tagBits)
  let typeSize = Size(bits: typeBits)
  return (typeSize, IntType(width: Int(typeBits), in: IGM.module.context))
}
