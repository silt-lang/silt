/// PassProtocol.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

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
