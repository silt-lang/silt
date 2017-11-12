/// Syntax.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

public final class TypeChecker<PhaseState> {
  var state: State<PhaseState>

  final class State<S> {
    var signature: Signature
    var environment: Environment
    var state: S

    init(_ signature: Signature, _ env: Environment, _ state: S) {
      self.signature = signature
      self.environment = env
      self.state = state
    }
  }

  public init(_ sig: Signature, _ env: Environment, _ state: PhaseState) {
    self.state = State<PhaseState>(sig, env, state)
  }

  public var signature: Signature {
    return self.state.signature
  }
}
