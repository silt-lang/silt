/// GIRBuilder.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere
import Moho

public final class GIRBuilder {
  public let module: GIRModule

  public init(module: GIRModule) {
    self.module = module
  }

  public func buildContinuation(name: QualifiedName) -> Continuation {
    let continuation = Continuation(name: name)
    module.addContinuation(continuation)
    return continuation
  }

  public func buildBBLikeContinuation(
    base: QualifiedName, tag: String
  ) -> Continuation {
    let continuation = Continuation(name: base, suffix: tag)
    module.addContinuation(continuation)
    return continuation
  }

  func insert<T: PrimOp>(_ primOp: T) -> T {
    module.addPrimOp(primOp)
    return primOp
  }

  public func removeContinuation(_ continuation: Continuation) {
    module.removeContinuation(continuation)
  }
}

extension GIRBuilder {
  public func createApply(
    _ parent: Continuation, _ fnVal: Value, _ argVals: [Value]) -> ApplyOp {
    return insert(ApplyOp(parent, fnVal, argVals))
  }

  public func createAllocBox(_ type: GIRType) -> AllocBoxOp {
    return insert(AllocBoxOp(type))
  }

  public func createDeallocBox(_ value: Value) -> DeallocBoxOp {
    return DeallocBoxOp(value)
  }

  public func createProjectBox(_ value: Value, type: GIRType) -> ProjectBoxOp {
    return insert(ProjectBoxOp(value, type: type))
  }

  public func createLoad(
    _ value: Value, _ ownership: LoadOp.Ownership
  ) -> LoadOp {
    return insert(LoadOp(value, ownership))
  }

  public func createStore(_ value: Value, to address: Value) -> StoreOp {
    return insert(StoreOp(value, to: address))
  }

  public func createAlloca(_ type: GIRType) -> AllocaOp {
    return insert(AllocaOp(type))
  }

  public func createDealloca(_ value: Value) -> DeallocaOp {
    return DeallocaOp(value)
  }

  public func createCopyValue(_ value: Value) -> CopyValueOp {
    return insert(CopyValueOp(value))
  }

  public func createDestroyValue(_ value: Value) -> DestroyValueOp {
    return DestroyValueOp(value)
  }

  public func createCopyAddress(
    _ value: Value, to address: Value) -> CopyAddressOp {
    return insert(CopyAddressOp(value, to: address))
  }

  public func createDestroyAddress(_ value: Value) -> DestroyAddressOp {
    return DestroyAddressOp(value)
  }

  public func createFunctionRef(_ cont: Continuation) -> FunctionRefOp {
    return insert(FunctionRefOp(continuation: cont))
  }

  public func createTuple(_ argVals: [Value]) -> TupleOp {
    return insert(TupleOp(arguments: argVals))
  }

  public func createTupleElementAddress(
    _ tuple: Value, _ index: Int
  ) -> TupleElementAddressOp {
    return insert(TupleElementAddressOp(tuple: tuple, index: index))
  }

  public func createThicken(_ f: FunctionRefOp) -> ThickenOp {
    return insert(ThickenOp(f))
  }

  public func createDataInit(
    _ constr: String, _ type: Value, _ arg: Value?
  ) -> DataInitOp {
    return insert(DataInitOp(constructor: constr, type: type, argument: arg))
  }

  public func createDataExtract(
    _ constr: String, _ value: Value, _ payloadType: Value
  ) -> DataExtractOp {
    return insert(DataExtractOp(constructor: constr, value: value,
                                payloadType: payloadType))
  }

  public func createSwitchConstr(
    _ parent: Continuation, _ src: Value, _ caseVals: [(String, FunctionRefOp)],
    _ default: FunctionRefOp? = nil
  ) -> SwitchConstrOp {
    return insert(SwitchConstrOp(parent, matching: src, patterns: caseVals,
                                 default: `default`))
  }

  public func createForceEffects(
    _ retVal: Value, _ effects: [Value]
  ) -> ForceEffectsOp {
    return insert(ForceEffectsOp.init(retVal, effects))
  }

  public func createUnreachable(_ parent: Continuation) -> UnreachableOp {
    return insert(UnreachableOp(parent: parent))
  }
}
