/// DiagnosticEngine.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public struct DiagnosticConsumerToken {
  internal let uuid: UUID
}

/// A DiagnosticEngine is a container for diagnostics that have been emitted
/// while compiling a silt program. It exposes an interface for emitting errors
/// and warnings and allows for iteration over diagnostics after the fact.
public final class DiagnosticEngine {
  /// The current set of emitted diagnostics.
  private(set) public var diagnostics = [Diagnostic]()

  /// The set of in-flight diagnostics for a particular transaction.
  private var transactionDiagnostics = [Int: [Diagnostic]]()

  /// The current transaction.
  private var activeTransaction: Int?

  /// The set of consumers receiving diagnostic notifications from this engine.
  private var consumers = [UUID: DiagnosticConsumer]()

  /// The next available (unique) transaction ID.
  private var transactionIDPool: Int = .min

  /// Creates a new DiagnosticEngine with no diagnostics registered.
  public init() {}

  /// Adds a diagnostic consumer to the engine to receive diagnostic updates.
  ///
  /// - Parameter consumer: The consumer that will observe diagnostics.
  /// - Returns: A token that can be used to unregister a consumer.
  @discardableResult
  public func register(
    _ consumer: DiagnosticConsumer) -> DiagnosticConsumerToken {
    let uuid = UUID()
    consumers[uuid] = consumer
    return DiagnosticConsumerToken(uuid: uuid)
  }

  /// Unregisters a consumer that's registered with the provided token.
  ///
  /// - Parameter token: The token returned when the consumer was registered.
  /// - Note: If the token was not registered with this diagnostic engine,
  ///         this function will cause a fatal error.
  public func unregister(_ token: DiagnosticConsumerToken) {
    guard consumers.removeValue(forKey: token.uuid) != nil else {
      fatalError("attempt to remove unregistered diagnostic consumer")
    }
  }

  /// Unregisters all consumers registered with this engine.
  public func unregisterConsumers() {
    consumers = [:]
  }

  /// Calls the given closure on each consumer registered with this diagnostic
  /// engine.
  public func forEachConsumer(_ action: (DiagnosticConsumer) -> Void) {
    self.consumers.values.forEach(action)
  }

  /// Determines if the engine has any `.error` diagnostics registered.
  public func hasErrors() -> Bool {
    return diagnostics.contains { $0.message.severity == .error }
  }

  /// Enter a diagnostic transaction delimited by a function that returns
  /// true if any diagnoses during the transaction should be emitted or false
  /// to ignore them all.
  public func transact<T>(_ f: () -> (shouldDiagnose: Bool, T)) -> T {
    defer { self.transactionIDPool += 1 }
    let lastTransactionID = self.activeTransaction
    let newUID = self.transactionIDPool
    self.activeTransaction = newUID
    let (commitDiags, result) = f()
    defer { self.activeTransaction = lastTransactionID }
    if commitDiags {
      guard
        let transactionDiagnostics = self.transactionDiagnostics[newUID]
      else {
        return result
      }

      for diagnostic in transactionDiagnostics {
        diagnostics.append(diagnostic)
        for consumer in consumers.values {
          consumer.handle(diagnostic)
        }
      }
    } else {
      self.transactionDiagnostics.removeValue(forKey: newUID)
    }
    return result
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
  @discardableResult
  public func diagnose(
    _ message: Diagnostic.Message, node: Syntax? = nil,
    actions: Diagnostic.BuildActions? = nil) -> Diagnostic.Message {
    let diagnostic = Diagnostic(message: message,
                                node: node,
                                actions: actions)

    if let activeID = self.activeTransaction {
      self.transactionDiagnostics[activeID, default: []].append(diagnostic)
      return message
    }

    diagnostics.append(diagnostic)
    for consumer in consumers.values {
      consumer.handle(diagnostic)
    }
    return message
  }
}
