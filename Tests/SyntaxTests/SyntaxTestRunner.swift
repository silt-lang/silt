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

var stdoutStream = FileHandle.standardOutput

enum Action {
  case describingTokens
  case dumpingParse
}

class SyntaxTestRunner: XCTestCase {
  func testSyntax() {
    let filesURL = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("Resources")
    guard let siltFiles = try? FileManager.default.contentsOfDirectory(at: filesURL, includingPropertiesForKeys: nil) else {
      XCTFail("Could not read silt files in directory")
      return
    }

    for file in siltFiles.filter({ $0.pathExtension == "silt" }) {
      guard let siltFile = try? String(contentsOfFile: file.path, encoding: .utf8) else {
        XCTFail("Could not read silt file at path \(file.absoluteString)")
        return
      }

      XCTAssert(fileCheckOutput(against: file.appendingPathExtension("syntax").path, options: [.disableColors]) {
        describe(siltFile, at: file.absoluteString, by: .describingTokens)
      })

      XCTAssert(fileCheckOutput(against: file.appendingPathExtension("ast").path, options: [.disableColors]) {
        describe(siltFile, at: file.absoluteString, by: .dumpingParse)
      })
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
    case .describingTokens:
      TokenDescriber.describe(tokens)
    case .dumpingParse:
      let parser = Parser(tokens: layoutTokens)
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
    ("testSyntax", testSyntax),
  ])
  #endif
}
