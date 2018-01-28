/// IRBuilder.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public final class IRBuilder {
  public let module: Module
  let env = Environment()

  public init(module: Module) {
    self.module = module
  }

  public func buildContinuation(name: String? = nil) -> Continuation {
    let continuation = Continuation(name: env.makeUnique(name))
    module.addContinuation(continuation)
    return continuation
  }
}
