/// DiagnosticGatePass.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

/// A DiagnosticGatePass is a pass that wraps another pass and throws away its
/// resulting value if any diagnostics were emitted.
/// This is useful for passes that only communicate failure via diagnostics,
/// like semantic analysis passes.
struct DiagnosticGatePass<PassTy: PassProtocol>: PassProtocol {
  /// The input of the underlying pass type.
  typealias Input = PassTy.Input

  /// The output of the underlying pass type.
  typealias Output = PassTy.Output

  var name: String {
    return pass.name
  }
  let pass: PassTy

  /// Creates a DiagnosticGatePass that wraps the provided pass.
  /// - parameter pass: The pass to gate on diagnostic emission.
  init(_ pass: PassTy) {
    self.pass = pass
  }

  /// Runs the underlying pass, but doesn't forward the value if the
  /// Diagnostic Engine registered an error.
  func run(_ input: Input, in context: PassContext) -> Output? {
    let output = pass.run(input, in: context)
    return context.engine.hasErrors() ? nil : output
  }
}
