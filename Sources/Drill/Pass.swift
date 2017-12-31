/// Pass.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

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
