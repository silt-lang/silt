/// PassComposition.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

/// A PassComposition, analogous to function composition, executes one pass
/// and pipes its output to the second pass. It converts two passes `(A) -> B`
/// and `(B) -> C` into one pass, `(A) -> C`.
struct PassComposition<PassA: PassProtocol, PassB: PassProtocol>: PassProtocol
  where PassA.Output == PassB.Input
{
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

/// An operator that represents a composition of passes.
infix operator |> : AdditionPrecedence


/// Composes two passes together into one pass.
///
/// - Parameters:
///   - passA: The first pass to run.
///   - passB: The second pass to run if the first succeeds.
/// - Returns: The output of the second pass, or `nil` if either pass failed.
func |> <PassA: PassProtocol, PassB: PassProtocol>(
  passA: PassA, passB: PassB) -> PassComposition<PassA, PassB> {
  return PassComposition(passA: passA, passB: passB)
}
