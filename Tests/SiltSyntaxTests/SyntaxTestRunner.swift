@testable import UpperCrust
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

    for token in tokens {
      print("Token:", "\(token.tokenKind)", terminator: "")
      if let loc = token.sourceRange?.start {
        print("<\(loc.file):\(loc.line):\(loc.column)>")
      }
      print("  Leading Trivia:")
      for piece in token.leadingTrivia.pieces {
        print("    \(piece)")
      }
      print("  Trailing Trivia:")
      for piece in token.trailingTrivia.pieces {
        print("    \(piece)")
      }
    }

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
