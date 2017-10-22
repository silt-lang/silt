/// DiagnosticTests.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import XCTest
import Lithosphere

extension Diagnostic.Message {
  static let errorWithNoNode =
    Diagnostic.Message(.error, "Error with no node attached")
  static let errorWithNoNodeAndNotes =
    Diagnostic.Message(.error, "Error with no node, but notes attached")
  static let highlightedNote =
    Diagnostic.Message(.note, "Note with a highlight attached")
  static let bareNote =
    Diagnostic.Message(.note, "A bare note with no node or highlights")
  static let warningWithANode =
    Diagnostic.Message(.warning, "A warning with a node attached")
  static let warningWithANodeAndHighlights =
    Diagnostic.Message(.warning, "A warning with a node and a highlight")
  static let warningWithEverything =
    Diagnostic.Message(.warning,
                       "A warning with a node, highlights, and a note")

  static func unexpectedToken(_ token: TokenSyntax) -> Diagnostic.Message {
    return Diagnostic.Message(.error,
                              "unexpected token '\(token.tokenKind.text)'")
  }
}

class DiagnosticTests: XCTestCase {
  var engine: DiagnosticEngine!

  override func setUp() {
    engine = DiagnosticEngine()
  }

  func testSimpleDiagnosticEmission() {
    engine.diagnose(.errorWithNoNode)

    let file = "foo.silt"
    let loc = SourceLocation(line: 0, column: 0, file: file, offset: 0)
    let range = SourceRange(start: loc, end: loc)
    let colon = TokenSyntax(.colon, sourceRange: range)

    engine.diagnose(.unexpectedToken(colon)) {
      $0.note(.highlightedNote, node: colon, highlights: [colon])
      $0.note(.bareNote)
    }

    engine.diagnose(.warningWithANode, node: colon)
    engine.diagnose(.warningWithANodeAndHighlights, node: colon) {
      $0.highlight(colon)
    }

    engine.diagnose(.warningWithEverything, node: colon) {
      $0.highlight(colon)
      $0.note(.bareNote, node: colon)
    }

    XCTAssertEqual(engine.diagnostics.count, 5)

    XCTAssertEqual(engine.diagnostics[0].notes.count, 0)
    XCTAssertEqual(engine.diagnostics[1].notes.count, 2)
    XCTAssertEqual(engine.diagnostics[2].notes.count, 0)
    XCTAssertEqual(engine.diagnostics[3].notes.count, 0)
    XCTAssertEqual(engine.diagnostics[4].notes.count, 1)

    XCTAssertEqual(engine.diagnostics[0].highlights.count, 0)
    XCTAssertEqual(engine.diagnostics[1].highlights.count, 0)
    XCTAssertEqual(engine.diagnostics[2].highlights.count, 0)
    XCTAssertEqual(engine.diagnostics[3].highlights.count, 1)
    XCTAssertEqual(engine.diagnostics[4].highlights.count, 1)
  }

  #if !os(macOS)
  static var allTests = testCase([
    ("testSimpleDiagnosticEmission", testSimpleDiagnosticEmission),
  ])
  #endif
}
