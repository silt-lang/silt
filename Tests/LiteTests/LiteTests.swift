/// LiteTests.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import XCTest
@testable import LiteSupport

class LiteTests: XCTestCase {

  func testCommonPrefix() {
    let strings = ["hello", "help", "heck"]
    XCTAssertEqual(strings.commonPrefix, "he")

    let strings2 = ["abc", "bcd", "cde"]
    XCTAssertEqual(strings2.commonPrefix, "")

    let largePrefix = String(repeating: "a", count: 50)
    let largeArray = [String](repeating: largePrefix, count: 1000)

    measure {
      XCTAssertEqual(largeArray.commonPrefix, largePrefix)
    }
  }

  func testTestRunner() {
    let testsDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
                                              .deletingLastPathComponent()
                                              .appendingPathComponent("Lite")
    do {
      let runner = try TestRunner(testDirPath: testsDir.path,
                                  siltExecutablePath: "/usr/bin/true")
      try XCTAssertFalse(runner.discoverTests().isEmpty)
    } catch {
      XCTFail("could not create test runner: \(error)")
    }
  }

  #if !os(macOS)
  static var allTests = testCase([
    ("testCommonPrefix", testCommonPrefix)
  ])
  #endif
}
