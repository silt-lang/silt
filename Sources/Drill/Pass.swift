/// Pass.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

/// A class that's passed to invocations of each pass. It contains a timer
/// and diagnostic engine that each pass can make use of.
class PassContext {
  let timer = PassTimer()
  let engine: DiagnosticEngine

  init(engine: DiagnosticEngine) {
    self.engine = engine
  }
}

/// Defines the set of behaviors of a compiler pass. Passes can be thought of
/// as functions from Input to Output, but which execute in a context.
protocol PassProtocol {
  /// The type of values that this pass consumes.
  associatedtype Input

  /// The type of output this pass transforms the Input into.
  associatedtype Output

  /// The display name of this pass (used for pass timing).
  var name: String { get }

  /// Runs this pass with the provided input in the provided context.
  /// - parameters:
  ///   - input: The input to this pass (usually output from a previous pass).
  ///   - context: The pass context this pass will be executed in.
  /// - returns: An optional transformed value based on the input. If this
  ///            pass failed, it should return `nil` from this method.
  func run(_ input: Input, in context: PassContext) -> Output?
}

/// A Pass is the most common currency for compiler passes. It wraps a function
/// with the same signature as `PassProtocol`'s `run` method, and is responsible
/// for invoking the pass timer before executing its actions.
struct Pass<In, Out>: PassProtocol {
  /// The input is generic to each pass.
  typealias Input = In

  /// The output is generic to each pass.
  typealias Output = Out

  let name: String
  let actions: (Input, PassContext) -> Output?

  /// Creates a new `Pass` with the given name and actions.
  /// - parameters:
  ///   - name: A displayable name for this pass.
  ///   - actions: A function that represents the body of the pass.
  init(name: String, actions: @escaping (Input, PassContext) -> Output?) {
    self.name = name
    self.actions = actions
  }

  /// Runs the provided actions, passing along the input and context.
  func run(_ input: In, in context: PassContext) -> Out? {
    return context.timer.measure(pass: name) {
      actions(input, context)
    }
  }
}

/// A PassComposition, analogous to function composition, executes one pass
/// and pipes its output to the second pass. It converts two passes `(A) -> B`
/// and `(B) -> C` into one pass, `(A) -> C`.
struct PassComposition<PassA: PassProtocol, PassB: PassProtocol>: PassProtocol
   where PassA.Output == PassB.Input {
  let name = "PassComposition"

  /// The first pass to execute.
  let passA: PassA

  /// The second pass to execute.
  let passB: PassB


  /// Runs the first pass and, if it returned a non-`nil` value, passes
  /// the value to the second pass and returns that value.
  ///
  /// - Parameters:
  ///   - input: The input to the first pass.
  ///   - context: The context in which to execute the passes.
  /// - Returns: The output of the second pass, or `nil` if either pass failed.
  func run(_ input: PassA.Input, in context: PassContext) -> PassB.Output? {
    return passA.run(input, in: context).flatMap {
      passB.run($0, in: context)
    }
  }
}

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

/// An operator that represents a composition of passes.
infix operator |> : AdditionPrecedence


/// Composes two passes together into one pass.
///
/// - Parameters:
///   - passA: The first pass to run.
///   - passB: The second pass to run if the first succeeds.
/// - Returns: The output of the second pass, or `nil` if either pass failed.
func |><PassA: PassProtocol, PassB: PassProtocol>(
  passA: PassA, passB: PassB) -> PassComposition<PassA, PassB> {
  return PassComposition(passA: passA, passB: passB)
}
