/// SyntaxTestRunner.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Drill
@testable import Lithosphere
import Crust
import XCTest
import Foundation
import FileCheck
import Rainbow
import Seismography

var stdoutStream = FileHandle.standardOutput

enum Action {
  case describingTokens
  case dumpingParse
  case dumpingShined
}

class SyntaxTestRunner: XCTestCase {
  var engine: DiagnosticEngine!
  var siltFiles = [URL]()

  override func setUp() {
    if siltFiles.isEmpty {
      let filesURL = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")
      do {
        let fm = FileManager.default
        siltFiles = try fm.contentsOfDirectory(at: filesURL,
                                               includingPropertiesForKeys: nil)
                          .filter { $0.pathExtension == "silt" }
      } catch {
        XCTFail("Could not read silt files in directory: \(error)")
      }
    }
    Rainbow.enabled = false
    engine = DiagnosticEngine()
    engine.register(XCTestFailureConsumer())
  }

  func filecheckEachSiltFile(adjustPath: (URL) -> URL,
                             actions: (String, String) -> Void) {
    for file in siltFiles {
      guard let contents = try? String(contentsOfFile: file.path,
                                       encoding: .utf8) else {
        XCTFail("Could not read silt file at path \(file.absoluteString)")
        return
      }

      let syntaxFile = adjustPath(file).path
      if FileManager.default.fileExists(atPath: syntaxFile) {
        XCTAssert(fileCheckOutput(against: .filePath(syntaxFile)) {
          actions(contents, file.path)
        }, "failed while dumping syntax file \(syntaxFile)")
      } else {
        XCTFail("no corresponding syntax file found at \(syntaxFile)")
      }
    }
  }

  func testAST() {
    filecheckEachSiltFile(adjustPath: { $0.appendingPathExtension("ast") }) {
      describe($0, at: $1, by: .dumpingParse)
    }
  }

  func testShined() {
    filecheckEachSiltFile(adjustPath: { $0.appendingPathExtension("shined") }) {
      describe($0, at: $1, by: .dumpingShined)
    }
  }

  func testSyntax() {
    filecheckEachSiltFile(adjustPath: { $0.appendingPathExtension("syntax") }) {
      describe($0, at: $1, by: .describingTokens)
    }
  }

  func describe(_ input: String, at path: String, by action: Action) {
    let lexer = Lexer(input: input, filePath: path)
    let tokens = lexer.tokenize()
    XCTAssert(tokens.map { $0.sourceText }.joined() == input,
              "Lexed tokens did not faithfully recreate input?")

    let layoutTokens = layout(tokens)
    XCTAssert(layoutTokens.map { $0.sourceText }.joined() == input,
              "Layout affected token stream!?")

    switch action {
    case .dumpingShined:
      for token in layoutTokens {
        token.writeSourceText(to: &stdoutStream, includeImplicit: true)
      }
    case .describingTokens:
      TokenDescriber.describe(tokens, to: &stdoutStream)
    case .dumpingParse:
      let parser = Parser(diagnosticEngine: engine, tokens: layoutTokens)
      guard let tlm = parser.parseTopLevelModule() else {
        XCTFail("Parsing top level module failed!")
        return
      }
      SyntaxDumper(stream: &stdoutStream).dump(tlm)
    }

    XCTAssert(tokens.map { $0.sourceText }.joined() == input)
  }

  #if !os(macOS)
  static var allTests = testCase([
    ("testAST", testAST),
    ("testSyntax", testSyntax),
    ("testShined", testShined),
  ])
  #endif
}
