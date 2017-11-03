/// DiagnosticVerifier.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

extension Diagnostic.Message {
  /// A diagnostic was produced that did not have an associated expectation.
  static func unexpectedDiagnostic(
    _ diagnostic: Diagnostic.Message) -> Diagnostic.Message {
    return .init(.error,
      "unexpected \(diagnostic.severity) produced: '\(diagnostic.text)'")
  }

  /// An expected diagnostic was never raised.
  static func diagnosticNotRaised(
    _ diagnostic: Diagnostic.Message) -> Diagnostic.Message {
    return .init(.error,
      "\(diagnostic.severity) \"\(diagnostic.text)\" never produced")
  }

  static func incorrectDiagnostic(
    got diagnostic: Diagnostic.Message) -> Diagnostic.Message {
    return .init(.error, "incorrect diagnostic '\(diagnostic.text)'")
  }

  static func expected(_ diagnostic: Diagnostic.Message) -> Diagnostic.Message {
    return .init(.note, "expected \(diagnostic.severity) '\(diagnostic.text)'")
  }

  /// A diagnostic was raised with no node attached.
  static func diagnosticWithNoNode(
    _ diagnostic: Diagnostic.Message) -> Diagnostic.Message {
    return .init(.error,
                 "diagnostic '\(diagnostic.text)' found with no location")
  }
}

/// A regex that matches expected(error|note|warning){{message}}, similar to
/// Swift and Clang's diagnostic verifiers.
//swiftlint:disable force_try
fileprivate let diagRegex = try! NSRegularExpression(pattern:
  "--\\s*expected-(error|note|warning)\\s*\\{\\{(.*)\\}\\}")

/// The DiagnosticVerifier is responsible for parsing diagnostic expectation
/// comments in a silt file and verifying that the set of diagnostics
/// produced during the compilation operation exactly matches, with no extras
/// or omissions, the set of expectation comments.
///
/// Expectation comments are written as standard silt comments, i.e.
public final class DiagnosticVerifier {

  /// Represents a parsed expectation containing a severity, a textual message,
  /// and the original token to which the comment was attached (for use in the
  /// final diagnostic to point near this comment).
  struct Expectation: Hashable {
    let message: Diagnostic.Message
    let tokenContainingComment: Syntax

    /// Compares two expectations to ensure they're the same.
    static func == (lhs: Expectation, rhs: Expectation) -> Bool {
      return lhs.message.text == rhs.message.text &&
             lhs.message.severity == rhs.message.severity &&
             lhs.tokenContainingComment.startLoc?.line ==
               rhs.tokenContainingComment.startLoc?.line
    }

    var hashValue: Int {
      return message.text.hashValue ^
             message.severity.rawValue.hashValue
    }
  }

  /// The set of expected-{severity} comments in the file.
  let expectedDiagnostics: Set<Expectation>

  /// The set of diagnostics that have been parsed.
  let producedDiagnostics: [Diagnostic]

  /// The temporary diagnostic engine into which we'll be pushing diagnostics
  /// for verification errors.
  let engine: DiagnosticEngine = {
    let e = DiagnosticEngine()
    e.register(PrintingDiagnosticConsumer(stream: &stderrStream))
    return e
  }()

  /// Creates a diagnostic verifier that uses the provided token stream and
  /// set of produced diagnostics to find and verify the set of expectations
  /// in the original file.
  public init(tokens: [TokenSyntax], producedDiagnostics: [Diagnostic]) throws {
    self.producedDiagnostics = producedDiagnostics
    self.expectedDiagnostics =
      DiagnosticVerifier.parseExpectations(tokens, engine: self.engine)
  }

  public func verify() {
    // Keep a list of expectations we haven't matched yet.
    var unmatchedExpectations = expectedDiagnostics

    // Maintain a list of unexpected diagnostics and the line they
    // occurred on.
    var unexpectedDiagnostics = [Int: Diagnostic]()

    // Go through each diagnostic we've produced.
    for diagnostic in producedDiagnostics {

      // Expectations require a line.
      guard let node = diagnostic.node, let loc = node.startLoc else {
        engine.diagnose(.diagnosticWithNoNode(diagnostic.message))
        continue
      }

      let expectation = Expectation(message: diagnostic.message,
                                    tokenContainingComment: node)

      // Make sure we're expecting this diagnostic.
      guard expectedDiagnostics.contains(expectation) else {
        unexpectedDiagnostics[loc.line] = diagnostic
        continue
      }

      // Remove it from the unmatched one, if we've seen it.
      unmatchedExpectations.remove(expectation)
    }

    // Diagnostics we never saw produced are errors -- make our own error
    // stating that.
    let expectations = unmatchedExpectations.sorted { a, b in
      guard let aLine = a.tokenContainingComment.startLoc?.line,
        let bLine = b.tokenContainingComment.startLoc?.line else {
          return false
      }
      return aLine < bLine
    }
    for expectation in expectations {
      if
        let line = expectation.tokenContainingComment.startLoc?.line,
        let unexpected = unexpectedDiagnostics[line] {
        engine.diagnose(.incorrectDiagnostic(got: unexpected.message),
                        node: unexpected.node) {
          $0.note(.expected(expectation.message), node: unexpected.node)
        }
        unexpectedDiagnostics.removeValue(forKey: line)
      } else {
        engine.diagnose(.diagnosticNotRaised(expectation.message),
                        node: expectation.tokenContainingComment)
      }
    }
    for diagnostic in unexpectedDiagnostics.values {
      engine.diagnose(.unexpectedDiagnostic(diagnostic.message),
                      node: diagnostic.node)
    }
  }

  /// Extracts a list of expectations from the comment trivia inside the
  /// provided token stream. This provides the set of expectations that the
  /// real diagnostics will be verified against.
  private static func parseExpectations(
    _ tokens: [TokenSyntax], engine: DiagnosticEngine) -> Set<Expectation> {
    var expectations = Set<Expectation>()
    for token in tokens {
      for trivia in token.leadingTrivia + token.trailingTrivia {
        guard case .comment(let text) = trivia else { continue }

        let nsString = NSString(string: text)
        let range = NSRange(location: 0, length: nsString.length)

        diagRegex.enumerateMatches(in: text,
                                   range: range) { result, _, _ in
          guard let result = result else { return }
          let severityRange = result.range(at: 1)
          let messageRange = result.range(at: 2)
          let rawSeverity = nsString.substring(with: severityRange)
          let message = nsString.substring(with: messageRange)
          let severity = Diagnostic.Message.Severity(rawValue: rawSeverity)!
          expectations.insert(Expectation(message: .init(severity, message),
                                          tokenContainingComment: token))
        }
      }
    }
    return expectations
  }
}
