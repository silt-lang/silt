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

  public func buildContinuation(name: String? = nil, type: Type = BottomType.shared) -> Continuation {
    let continuation = Continuation(name: env.makeUnique(name), type: type)
    module.addContinuation(continuation)
    return continuation
  }

  func insert<T: PrimOp>(_ primOp: T) -> T {
    module.addPrimOp(primOp)
    return primOp
  }
}

extension IRBuilder {
  public func createApply(_ fnVal: Value, _ argVals: [Value]) -> ApplyOp {
    return insert(ApplyOp(fnVal, argVals))
  }

  public func createCopyValue(_ value: Value) -> CopyValueOp {
    return insert(CopyValueOp(value))
  }

  public func createDestroyValue(_ value: Value) -> DestroyValueOp {
    return insert(DestroyValueOp(value))
  }
}
