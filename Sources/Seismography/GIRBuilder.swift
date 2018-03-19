/// GIRBuilder.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public final class GIRBuilder {
  public let module: GIRModule

  public init(module: GIRModule) {
    self.module = module
  }

  public func buildContinuation(name: String) -> Continuation {
    let continuation = Continuation(name: name)
    module.addContinuation(continuation)
    return continuation
  }

  func insert<T: PrimOp>(_ primOp: T) -> T {
    module.addPrimOp(primOp)
    return primOp
  }
}

extension GIRBuilder {
  public func createApply(
    _ parent: Continuation, _ fnVal: Value, _ argVals: [Value]) -> ApplyOp {
    return insert(ApplyOp(parent, fnVal, argVals))
  }

  public func createCopyValue(_ value: Value) -> CopyValueOp {
    return insert(CopyValueOp(value))
  }

  public func createDestroyValue(
    _ value: Value, in cont: Continuation) -> DestroyValueOp {
    let destroy = insert(DestroyValueOp(value))
    cont.appendDestroyable(destroy)
    return destroy
  }

  public func createFunctionRef(_ cont: Continuation) -> FunctionRefOp {
    return insert(FunctionRefOp(continuation: cont))
  }

  public func createDataInit(_ constr: String, _ type: Value, _ args: [Value]) -> DataInitOp {
    return insert(DataInitOp(constructor: constr, type: type, arguments: args))
  }

  public func createSwitchConstr(
    _ parent: Continuation, _ src: Value, _ caseVals: [(String, Value)],
    _ default: Value? = nil
  ) -> SwitchConstrOp {
    return insert(SwitchConstrOp(parent, matching: src, patterns: caseVals,
                                 default: `default`))
  }

  public func createUnreachable(_ parent: Continuation) -> UnreachableOp {
    return insert(UnreachableOp(parent: parent))
  }
}
