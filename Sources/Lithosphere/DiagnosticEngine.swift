/// DiagnosticEngine.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// A DiagnosticEngine is a container for diagnostics that have been emitted
/// while compiling a silt program. It exposes an interface for emitting errors
/// and warnings and allows for iteration over diagnostics after the fact.
public final class DiagnosticEngine {
  /// The current set of emitted diagnostics.
  private(set) public var diagnostics = [Diagnostic]()

  /// The set of consumers receiving diagnostic notifications from this engine.
  private(set) public var consumers = [DiagnosticConsumer]()

  /// Creates a new DiagnosticEngine with no diagnostics registered.
  public init() {}

  /// Adds a diagnostic consumer to the engine to receive diagnostic updates.
  ///
  /// - Parameter consumer: The consumer that will observe diagnostics.
  public func register(_ consumer: DiagnosticConsumer) {
    consumers.append(consumer)
  }

  /// Emits a diagnostic message into the engine.
  ///
  /// - Parameters:
  ///   - message: The message for the given diagnostic. This should include
  ///              details about what specific invariant is being violated
  ///              by the code.
  ///   - node: The node the diagnostic is attached to, or `nil` if the
  ///           diagnostic is meant to apply to the entire compilation.
  ///   - actions: A closure to execute to incrementally add highlights and
  ///              notes to a Syntax node.
  public func diagnose(_ message: Diagnostic.Message, node: Syntax? = nil,
                       actions: Diagnostic.BuildActions? = nil) {
    let diagnostic = Diagnostic(message: message,
                                node: node,
                                actions: actions)
    diagnostics.append(diagnostic)
    for consumer in consumers {
      consumer.handle(diagnostic)
    }
  }
}
