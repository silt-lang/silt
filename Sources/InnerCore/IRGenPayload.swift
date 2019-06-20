import LLVM
import Seismography
import OuterCore
import Mantle

/// A payload value represented as an explosion of integers and pointers that
/// together represent the bit pattern of the payload.
final class Payload {
  enum Schema {
    case dynamic
    case bits(UInt64)
    case schema(Explosion.Schema)

    func forEachType(_ IGM: IRGenModule, _ fn: (IRType) -> Void) {
      switch self {
      case .dynamic:
        break
      case let .schema(explosion):
        for element in explosion.elements {
          let type = element.scalarType
          assert(IGM.dataLayout.sizeOfTypeInBits(type)
              == IGM.dataLayout.allocationSize(of: type),
                 "enum payload schema elements should use full alloc size")
          fn(type)
        }
      case .bits(var bitSize):
        let pointerSize = IGM.getPointerSize().valueInBits()
        while bitSize >= pointerSize {
          fn(IGM.dataLayout.intPointerType())
          bitSize -= pointerSize
        }
        if bitSize > 0 {
          fn(IntType(width: Int(bitSize), in: IGM.module.context))
        }
      }
    }

    var isStatic: Bool {
      switch self {
      case .dynamic:
        return false
      default:
        return true
      }
    }
  }

  var payloadValues = [Either<IRValue, IRType>]()
  private var storageTypeCache: IRType?

  init() { }

  private init(raw payloadValues: [Either<IRValue, IRType>]) {
    self.payloadValues = payloadValues
  }

  /// Generate a "zero" enum payload.
  static func zero(_ IGM: IRGenModule, _ schema: Payload.Schema) -> Payload {
    // We don't need to create any values yet they can be filled in when
    // real values are inserted.
    var result = [Either<IRValue, IRType>]()
    schema.forEachType(IGM) { type in
      result.append(.right(type))
    }
    return Payload(raw: result)
  }

  static func fromExplosion(
    _ IGM: IRGenModule, _ source: Explosion, _ schema: Payload.Schema
  ) -> Payload {
    var result = [Either<IRValue, IRType>]()
    schema.forEachType(IGM) { _ in
      result.append(.left(source.claimSingle()))
    }
    return Payload(raw: result)
  }

  /// Generate an enum payload containing the given bit pattern.
  static func fromBitPattern(
    _ IGM: IRGenModule, _ bitPattern: APInt, _ schema: Payload.Schema
  ) -> Payload {
    var result = [Either<IRValue, IRType>]()

    var bitPattern = bitPattern
    schema.forEachType(IGM) { type in
      let bitSize = IGM.dataLayout.sizeOfTypeInBits(type)

      // Take some bits off of the bottom of the pattern.
      var val: IRConstant = bitPattern.zeroExtendOrTruncate(to: bitSize)
      if val.type.asLLVM() != type.asLLVM() {
        val = val.bitCast(to: type)
      }

      result.append(.left(val))

      // Shift the remaining bits down.
      bitPattern.logicallyShiftRight(by: UInt64(bitSize))
    }

    return Payload(raw: result)
  }

  func packIntoEnumPayload(
    _ IGF: IRGenFunction, _ outerPayload: Payload, _ offset: Size
  ) {
    var bitOffset = offset
    let layout = IGF.IGM.dataLayout
    for value in self.payloadValues {
      let v = self.forcePayloadValue(value)
      outerPayload.insertValue(IGF, v, bitOffset)
      bitOffset += Size(layout.sizeOfTypeInBits(v.type))
    }
  }

  static func unpackFromPayload(
    _ IGF: IRGenFunction, _ outerPayload: Payload,
    _ offset: Size, _ schema: Payload.Schema
  ) -> Payload {
    var bitOffset = offset
    var result = [Either<IRValue, IRType>]()
    let DL = IGF.IGM.dataLayout
    schema.forEachType(IGF.IGM) { type in
      let v = outerPayload.extractValue(IGF, type, bitOffset)
      result.append(.left(v))
      bitOffset += Size(DL.sizeOfTypeInBits(type))
    }
    return Payload(raw: result)
  }
}

extension Payload {
  static func load(
    _ IGF: IRGenFunction, _ address: Address, _ schema: Payload.Schema
  ) -> Payload {
    let result = Payload.zero(IGF.IGM, schema)
    guard !result.payloadValues.isEmpty else {
      return result
    }

    let storageTy = result.llvmType(in: IGF.IGM.module.context)
    let ptrTy = PointerType(pointee: storageTy)
    let address = IGF.B.createPointerBitCast(of: address, to: ptrTy)

    if result.payloadValues.count == 1 {
      let val = IGF.B.createLoad(address, alignment: address.alignment)
      result.payloadValues[0] = .left(val)
    } else {
      var offset = Size.zero
      var loadedPayloads = [Either<IRValue, IRType>]()
      loadedPayloads.reserveCapacity(result.payloadValues.count)
      for i in result.payloadValues.indices {
        let member = IGF.B.createStructGEP(address, i, offset, "")
        let loadedValue =  IGF.B.createLoad(member,
                                            alignment: member.alignment)
        loadedPayloads.append(.left(loadedValue))
        offset += Size(IGF.IGM.dataLayout.allocationSize(of: loadedValue.type))
      }
      result.swapPayloadValues(for: loadedPayloads)
    }

    return result
  }

  func store(_ IGF: IRGenFunction, _ address: Address) {
    guard !self.payloadValues.isEmpty else {
      return
    }

    let storageTy = self.llvmType(in: IGF.IGM.module.context)
    let ptrTy = PointerType(pointee: storageTy)
    let address = IGF.B.createPointerBitCast(of: address, to: ptrTy)

    if self.payloadValues.count == 1 {
      IGF.B.buildStore(forcePayloadValue(self.payloadValues[0]),
                       to: address.address)
      return
    } else {
      var offset = Size.zero
      for (i, value) in self.payloadValues.enumerated() {
        let member = IGF.B.createStructGEP(address, i, offset, "")
        let valueToStore = forcePayloadValue(value)
        IGF.B.buildStore(valueToStore, to: member.address)
        offset += Size(IGF.IGM.dataLayout.allocationSize(of: valueToStore.type))
      }
    }
  }

  func swapPayloadValues(for other: [Either<IRValue, IRType>]) {
    self.payloadValues = other
  }

  func explode(_ IGM: IRGenModule, _ out: Explosion) {
    for value in self.payloadValues {
      out.append(forcePayloadValue(value))
    }
  }

  func llvmType(in context: LLVM.Context) -> IRType {
    if let ty = self.storageTypeCache {
      return ty
    }

    if self.payloadValues.count == 1 {
      self.storageTypeCache = self.getPayloadType(self.payloadValues[0])
      return self.storageTypeCache!
    }

    var elementTypes = [IRType]()
    for value in self.payloadValues {
      elementTypes.append(self.getPayloadType(value))
    }

    let type = StructType(elementTypes: elementTypes,
                          isPacked: false, in: context)
    self.storageTypeCache = type
    return type
  }

  func insertValue(
    _ IGF: IRGenFunction, _ value: IRValue,
    _ payloadOffset: Size, _ numBitsUsedInValue: Int? = nil
  ) {
    self.withValueInPayload(
      IGF, value.type, numBitsUsedInValue, payloadOffset
    ) { payloadValue, payloadWidth, payloadValueOff, valueBitWidth, valueOff in
      let payloadType = getPayloadType(payloadValue)
      // See if the value matches the payload type exactly. In this case we
      // don't need to do any work to use the value.
      if payloadValueOff == 0 && valueOff == 0 {
        if value.type.asLLVM() == payloadType.asLLVM() {
          payloadValue = .left(value)
          return
        }
        // If only the width matches exactly, we can still do a bitcast.
        if payloadWidth == valueBitWidth {
          let bitcast = IGF.B.createBitOrPointerCast(value, to: payloadType)
          payloadValue = .left(bitcast)
          return
        }
      }

      // Select out the chunk of the value to merge with the existing payload.
      var subvalue = value

      let valueIntTy = IntType(width: valueBitWidth,
                               in: IGF.IGM.module.context)
      let payloadIntTy = IntType(width: payloadWidth,
                                 in: IGF.IGM.module.context)
      let payloadTy = getPayloadType(payloadValue)
      subvalue = IGF.B.createBitOrPointerCast(subvalue, to: valueIntTy)
      if valueOff > 0 {
        subvalue = IGF.B.buildShr(subvalue,
                                  valueIntTy.constant(valueOff),
                                  isArithmetic: false)
      }
      subvalue = IGF.B.buildZExt(subvalue, type: payloadIntTy)

      if payloadValueOff > 0 {
        subvalue = IGF.B.buildShl(subvalue,
                                  payloadIntTy.constant(payloadValueOff))
      }
      switch payloadValue {
      case .right(_):
        // If there hasn't yet been a value stored here, we can use the adjusted
        // value directly.
        payloadValue = .left(IGF.B.createBitOrPointerCast(subvalue,
                                                          to: payloadTy))
      case let .left(val):
        // Otherwise, bitwise-or it in, brazenly assuming there are zeroes
        // underneath.
        // TODO: This creates a bunch of bitcasting noise for non-integer
        // payload fields.
        var lastValue = val
        lastValue = IGF.B.createBitOrPointerCast(lastValue, to: payloadIntTy)
        lastValue = IGF.B.buildOr(lastValue, subvalue)
        payloadValue = .left(IGF.B.createBitOrPointerCast(lastValue,
                                                          to: payloadTy))
      }
    }
  }

  func extractValue(
    _ IGF: IRGenFunction, _ type: IRType, _ offset: Size
  ) -> IRValue {
    var result = type.undef()
    self.withValueInPayload(
      IGF, type, nil, offset
    ) { payloadValue, payloadWidth, payloadValueOffset, valueWidth, valueOff in
      let payloadType = getPayloadType(payloadValue)
      // If the desired type matches the payload slot exactly, we don't need
      // to do anything.
      if payloadValueOffset == 0 && valueOff == 0 {
        if type.asLLVM() == payloadType.asLLVM() {
          result = forcePayloadValue(payloadValue)
          return
        }
        // If only the width matches exactly, do a bitcast.
        if payloadWidth == valueWidth {
          result =
            IGF.B.createBitOrPointerCast(forcePayloadValue(payloadValue),
                                         to: type)
          return
        }
      }

      // Integrate the chunk of payload into the result value.
      var value = forcePayloadValue(payloadValue)
      let valueIntTy = IntType(width: valueWidth,
                               in: IGF.IGM.module.context)
      let payloadIntTy = IntType(width: payloadWidth,
                                 in: IGF.IGM.module.context)

      value = IGF.B.createBitOrPointerCast(value, to: payloadIntTy)
      if payloadValueOffset > 0 {
        value = IGF.B.buildShr(value, valueIntTy.constant(payloadValueOffset))
      }
      if valueWidth > payloadWidth {
        value = IGF.B.buildZExt(value, type: valueIntTy)
      }
      if valueOff > 0 {
        value = IGF.B.buildShl(value, valueIntTy.constant(valueOff))
      }
      if valueWidth < payloadWidth {
        value = IGF.B.buildTrunc(value, type: valueIntTy)
      }
      if !result.isUndef {
        result = value
      } else {
        result = IGF.B.buildOr(result, value)
      }
    }
    return IGF.B.createBitOrPointerCast(result, to: type)
  }

  private func withValueInPayload(
    _ IGF: IRGenFunction, _ valueType: IRType, _ numBitsUsedInValue: Int?,
    _ payloadOffset: Size,
    _ f: (inout Either<IRValue, IRType>, Int, Int, Int, Int) -> Void
  ) {
    let DataLayout = IGF.IGM.dataLayout
    let valueTypeBitWidth = DataLayout.sizeOfTypeInBits(valueType)
    let valueBitWidth = numBitsUsedInValue ?? valueTypeBitWidth

    // Find the elements we need to touch.
    // TODO: Linear search through the payload elements is lame.
    var payloadType: IRType
    var payloadBitWidth: Int = 0
    var valueOffset = 0
    var payloadValueOffset = Int(payloadOffset.rawValue)
    for idx in self.payloadValues.indices {
      payloadType = getPayloadType(self.payloadValues[idx])
      payloadBitWidth = DataLayout.sizeOfTypeInBits(payloadType)

      // Does this element overlap the area we need to touch?
      if payloadValueOffset < payloadBitWidth {
        // See how much of the value we can fit here.
        var valueChunkWidth = payloadBitWidth - payloadValueOffset
        valueChunkWidth = min(valueChunkWidth, valueBitWidth - valueOffset)

        var val = self.payloadValues[idx]
        f(&val,
          payloadBitWidth, payloadValueOffset,
          valueTypeBitWidth, valueOffset)
        self.payloadValues[idx] = val

        valueOffset += valueChunkWidth

        // If we used the entire value, we're done.
        guard valueOffset < valueBitWidth else {
          return
        }
      }

      payloadValueOffset = max(payloadValueOffset - payloadBitWidth, 0)
    }
  }

  private func forcePayloadValue(_ value: Either<IRValue, IRType>) -> IRValue {
    switch value {
    case let .left(val):
      return val
    case let .right(ty):
      return ty.constPointerNull()
    }
  }

  private func getPayloadType(_ value: Either<IRValue, IRType>) -> IRType {
    switch value {
    case let .left(val):
      return val.type
    case let .right(ty):
      return ty
    }
  }
}
