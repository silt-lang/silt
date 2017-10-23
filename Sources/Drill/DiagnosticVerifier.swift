/// DiagnosticVerifier.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

extension Diagnostic.Message {
  static func unexpectedDiagnostic(
    _ diagnostic: Diagnostic.Message) -> Diagnostic.Message {
    return .init(.error,
      "unexpected \(diagnostic.severity) produced: '\(diagnostic.text)'")
  }
  static func diagnosticNotRaised(
    _ diagnostic: Diagnostic.Message) -> Diagnostic.Message {
    return .init(.error,
      "\(diagnostic.severity) \"\(diagnostic.text)\" never produced")
  }
  static func diagnosticWithNoLine(
    _ diagnostic: Diagnostic.Message) -> Diagnostic.Message {
    return .init(.error,
                 "diagnostic '\(diagnostic.text)' found with no location")
  }
}

/// A regex that matches expected(error|note|warning)
fileprivate let diagRegex = try! NSRegularExpression(pattern:
  "--\\s*expected-(error|note|warning)\\s*\\{\\{(.*)\\}\\}")

final class DiagnosticVerifier {
  struct Expectation: Hashable {
    let message: Diagnostic.Message
    let line: Int

    static func ==(lhs: Expectation, rhs: Expectation) -> Bool {
      return lhs.message.text == rhs.message.text &&
             lhs.message.severity == rhs.message.severity &&
             lhs.line == rhs.line
    }

    var hashValue: Int {
      return message.text.hashValue ^
             message.severity.rawValue.hashValue ^
             line.hashValue
    }
  }
  let expectedDiagnostics: Set<Expectation>
  let producedDiagnostics: [Diagnostic]
  let engine = DiagnosticEngine()

  init(file: URL, producedDiagnostics: [Diagnostic]) throws {
    self.engine.register(PrintingDiagnosticConsumer(stream: &stderrStream))
    let lines = try String(contentsOf: file).split(separator: "\n")
                                            .map(String.init)
    self.producedDiagnostics = producedDiagnostics
    self.expectedDiagnostics =
      DiagnosticVerifier.parseDiagnostics(lines, engine: self.engine)
  }

  func verify() {
    // Keep a list of expectations we haven't matched yet.
    var unmatchedExpectations = expectedDiagnostics

    // Go through each diagnostic we've produced.
    for diagnostic in producedDiagnostics {

      // Expectations require a line.
      guard let line = diagnostic.node?.startLoc?.line else {
        engine.diagnose(.diagnosticWithNoLine(diagnostic.message))
        continue
      }
      let expectation = Expectation(message: diagnostic.message, line: line)

      // Make sure we're expecting this diagnostic.
      guard expectedDiagnostics.contains(expectation) else {
        engine.diagnose(.unexpectedDiagnostic(diagnostic.message))
        continue
      }

      // Remove it from the unmatched one, if we've seen it.
      unmatchedExpectations.remove(expectation)
    }

    // Diagnostics we never saw produced are errors -- make our own error
    // stating that.
    for expectation in unmatchedExpectations.sorted(by: { $0.line < $1.line }) {
      engine.diagnose(.diagnosticNotRaised(expectation.message))
    }
  }

  static func parseDiagnostics(_ lines: [String],
                               engine: DiagnosticEngine) -> Set<Expectation> {
    var expectations = Set<Expectation>()
    for (offset, line) in lines.enumerated() {
      let nsString = NSString(string: line)
      let range = NSRange(location: 0, length: nsString.length)
      diagRegex.enumerateMatches(in: line,
                                 range: range) { result, flags, _ in
        guard let result = result else { return }
        let severityRange = result.range(at: 1)
        let messageRange = result.range(at: 2)
        let rawSeverity = nsString.substring(with: severityRange)
        let message = nsString.substring(with: messageRange)
        let severity = Diagnostic.Message.Severity(rawValue: rawSeverity)!
        expectations.insert(Expectation(message: .init(severity, message),
                                        line: offset + 1))
      }
    }
    return expectations
  }
}
