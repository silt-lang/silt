/// SyntaxTestRunner.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
@testable import Lithosphere
import Crust
import XCTest
import Foundation
import FileCheck

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
        describe(siltFile, at: file.absoluteString)
      })
    }
  }

  func describe(_ input: String, at path: String) {
    let lexer = Lexer(input: input, filePath: path)
    let tokens = lexer.tokenize()

    TokenDescriber.describe(tokens)

    XCTAssert(tokens.map { $0.sourceText }.joined() == input)

    //  do {
    //    var stdout = FileHandle.standardOutput
    //    let parser = Parser(tokens: tokens)
    //    let node = try parser.parseType()
    //    let dumper = SyntaxDumper(stream: &stdout)
    //    dumper.dump(node)
    //    print("Parsed: \(node.sourceText)")
    //  } catch {
    //    print("error: \(error)")
    //  }
  }

  #if !os(macOS)
  static var allTests = testCase([
    ("testSyntax", testSyntax),
  ])
  #endif
}
