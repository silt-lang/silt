/// IRBuilder.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public final class IRBuilder {
  public let module: GIRModule
  let env = Environment()

  public init(module: GIRModule) {
    self.module = module
  }

  public func buildContinuation(name: String, type: Type = BottomType.shared) -> Continuation {
    let continuation = Continuation(name: name, type: type)
    module.addContinuation(continuation)
    return continuation
  }

  func insert<T: PrimOp>(_ primOp: T) -> T {
    module.addPrimOp(primOp)
    return primOp
  }

  func insert<T: TerminalOp>(_ primOp: T) -> T {
    module.addPrimOp(primOp)
    // Tie the knot
    primOp.parent.terminalOp = primOp
    return primOp
  }

  func insert(
    _ primOp: DestroyValueOp, in cont: Continuation) -> DestroyValueOp {
    module.addPrimOp(primOp)
    cont.destroys.append(primOp)
    return primOp
  }
}

extension IRBuilder {
  public func createApply(_ parent: Continuation, _ fnVal: Value, _ argVals: [Value]) -> ApplyOp {
    return insert(ApplyOp(parent, fnVal, argVals))
  }

  public func createCopyValue(_ value: Value) -> CopyValueOp {
    return insert(CopyValueOp(value))
  }

  public func createDestroyValue(
    _ value: Value, in cont: Continuation) -> DestroyValueOp {
    return insert(DestroyValueOp(value), in: cont)
  }

  public func createFunctionRef(_ cont: Continuation) -> FunctionRefOp {
    return insert(FunctionRefOp(continuation: cont))
  }

  public func createDataInitSimple(_ constr: String) -> DataInitSimpleOp {
    return insert(DataInitSimpleOp(constructor: constr))
  }

  public func createSwitchConstr(
    _ parent: Continuation, _ src: Value, _ caseVals: [(String, Value)]) -> SwitchConstrOp {
    return insert(SwitchConstrOp(parent, matching: src, patterns: caseVals))
  }
}
