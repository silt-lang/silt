/// DiagnosticVerifier.swift
///
/// Copyright 2017-2018, The Silt Language Project.
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
    _ expectation: DiagnosticVerifier.Expectation) -> Diagnostic.Message {
    return .init(.error,
      "\(expectation.severity) \"\(expectation.messageText)\" never produced")
  }

  static func incorrectDiagnostic(
    got diagnostic: Diagnostic.Message) -> Diagnostic.Message {
    return .init(.error, "incorrect diagnostic '\(diagnostic.text)'")
  }

  static func expected(
    _ expectation: DiagnosticVerifier.Expectation) -> Diagnostic.Message {
    return .init(.note,
      "expected \(expectation.severity) '\(expectation.messageText)'")
  }

  /// A diagnostic was raised with no node attached.
  static func diagnosticWithNoNode(
    _ diagnostic: Diagnostic.Message) -> Diagnostic.Message {
    return .init(.error,
                 "diagnostic '\(diagnostic.text)' found with no location")
  }

  static func couldNotReadInput(_ url: URL) -> Diagnostic.Message {
    return .init(.error, "could not read input file at '\(url.path)'")
  }
}

/// A regex that matches expected-(error|note|warning) @<line>, similar to
/// Swift and Clang's diagnostic verifiers.
//swiftlint:disable force_try
private let diagWithLineRegex = try! NSRegularExpression(pattern:
  "--\\s*expected-(error|note|warning)\\s*@(-?\\d+)\\s+\\{\\{")

/// A regex that matches expected-(error|note|warning), similar to
/// Swift and Clang's diagnostic verifiers.
//swiftlint:disable force_try
private let diagRegex = try! NSRegularExpression(pattern:
  "--\\s*expected-(error|note|warning)\\s*\\{\\{")

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
    let messageText: String
    let messageRegex: NSRegularExpression
    let severity: Diagnostic.Message.Severity
    let line: Int

    /// Compares two expectations to ensure they're the same.
    static func == (lhs: Expectation, rhs: Expectation) -> Bool {
      return lhs.messageText == rhs.messageText &&
             lhs.severity == rhs.severity &&
             lhs.line == rhs.line
    }

    var hashValue: Int {
      return messageText.hashValue ^
             severity.rawValue.hashValue ^
             line.hashValue
    }
  }

  /// The set of expected-{severity} comments in the file.
  let expectations: [Expectation]

  /// The set of diagnostics that have been parsed.
  let producedDiagnostics: [(message: Diagnostic.Message, node: Syntax?)]

  /// The temporary diagnostic engine into which we'll be pushing diagnostics
  /// for verification errors.
  public let engine: DiagnosticEngine = {
    let e = DiagnosticEngine()
    e.register(PrintingDiagnosticConsumer(stream: &stderrStreamHandle))
    return e
  }()

  /// Creates a diagnostic verifier that uses the provided token stream and
  /// set of produced diagnostics to find and verify the set of expectations
  /// in the original file.
  public init(url: URL, producedDiagnostics: [Diagnostic]) {
    // Combine both the diagnostics and their notes into one big set of
    // node/message pairs.
    self.producedDiagnostics =
      producedDiagnostics.flatMap {
        [($0.message, $0.node)] + $0.notes.map {
          ($0.message, $0.node)
        }
      }
    self.expectations =
      DiagnosticVerifier.parseExpectations(url: url, engine: self.engine)
  }

  private func matches(message: Diagnostic.Message,
                       node: Syntax?,
                       expectation: Expectation) -> Bool {
    let expectedLine = expectation.line
    if expectedLine != node?.startLoc?.line {
      return false
    }
    let nsString = NSString(string: message.text)
    let range = NSRange(location: 0, length: nsString.length)
    let match = expectation.messageRegex.firstMatch(in: message.text,
                                                    range: range)
    return match != nil
  }

  public func verify() {
    // There's nothing to verify if we've already registered an error in
    // our diagnostic engine.
    if self.engine.hasErrors() { return }

    // Keep a list of expectations we haven't matched yet.
    var unmatched = expectations

    // Maintain a list of unexpected diagnostics and the line they
    // occurred on.
    var unexpected = [Int: [(Diagnostic.Message, Syntax?)]]()

    // Go through each diagnostic we've produced.
    for (message, node) in producedDiagnostics {

      // Expectations require a line.
      guard let node = node, let loc = node.startLoc else {
        engine.diagnose(.diagnosticWithNoNode(message))
        continue
      }

      // If any of the as-of-yet unmatched expectations fit this diagnostic,
      // remove it.
      if let idx = unmatched.index(where: { exp in
        return matches(message: message, node: node, expectation: exp)
      }) {
        unmatched.remove(at: idx)
      } else {
        unexpected[loc.line, default: []].append((message, node))
      }
    }

    // Diagnostics we never saw produced are errors -- make our own error
    // stating that.
    let remaining = unmatched.sorted { $0.line < $1.line }
    for expectation in remaining {
      if let diags = unexpected[expectation.line] {
        for (message, node) in diags {
          engine.diagnose(.incorrectDiagnostic(got: message),
                          node: node) {
            $0.note(.expected(expectation), node: node)
          }
        }
        unexpected.removeValue(forKey: expectation.line)
      } else {
        engine.diagnose(.diagnosticNotRaised(expectation))
      }
    }
    for (message, node) in unexpected.values.flatMap({ $0 }) {
      engine.diagnose(.unexpectedDiagnostic(message),
                      node: node)
    }
  }



  private static func parseExpectation(_ line: String,
                                       lineNumber: Int) -> Expectation? {
    let nsString = NSString(string: line)
    let range = NSRange(location: 0, length: nsString.length)
    let match: NSTextCheckingResult
    var lineOffset = 0

    if let _match = diagWithLineRegex.firstMatch(in: line, range: range) {
      match = _match
      let offsetStr = nsString.substring(with: match.range(at: 2))
      lineOffset = Int(offsetStr) ?? 0
    } else if let _match = diagRegex.firstMatch(in: line, range: range) {
      match = _match
    } else {
      return nil
    }

    let severityRange = match.range(at: 1)
    let rawSeverity = nsString.substring(with: severityRange)
    let severity = Diagnostic.Message.Severity(rawValue: rawSeverity)!
    var remainder = nsString.substring(from: match.range(at: 0).upperBound)
    if remainder.hasSuffix("}}") {
      remainder.removeLast(2)
    }
    guard
      let regex = DiagnosticRegexParser.parseMessageAsRegex(remainder) else {
        return nil
    }

    return Expectation(messageText: remainder,
                       messageRegex: regex,
                       severity: severity,
                       line: lineNumber + lineOffset)
  }

  /// Extracts a list of expectations from the comment trivia inside the
  /// provided token stream. This provides the set of expectations that the
  /// real diagnostics will be verified against.
  private static func parseExpectations(
    url: URL, engine: DiagnosticEngine) -> [Expectation] {
    var expectations = [Expectation]()
    guard let input = try? String(contentsOf: url, encoding: .utf8) else {
      engine.diagnose(.couldNotReadInput(url))
      return []
    }
    let lines = input.split(separator: "\n",
                            omittingEmptySubsequences: false)
    for (lineNum, line) in lines.enumerated() {
      guard let exp = parseExpectation(String(line),
                                       lineNumber: lineNum + 1) else {
        continue
      }
      expectations.append(exp)
    }
    return expectations
  }
}
