/// TestRunner.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

#if os(Linux)
/// HACK: This is needed because on macOS, ObjCBool is a distinct type
///       from Bool. On Linux, however, it is a typealias.
extension ObjCBool {
  /// Converts the ObjCBool value to a Swift Bool.
  var boolValue: Bool { return self }
}
#endif

class TestRunner {
  private var passes = 0
  private var failures = 0
  let testDir: URL
  let siltExecutable: URL

  init(testDirPath: String, siltExecutablePath: String) throws {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: testDirPath, isDirectory: &isDir) else {
      throw Diagnostic.Message.couldNotOpenTestDir(testDirPath)
    }
    guard isDir.boolValue else {
      throw Diagnostic.Message.testDirIsNotDirectory(testDirPath)
    }
    guard fm.fileExists(atPath: siltExecutablePath) else {
      throw Diagnostic.Message.couldNotFindSilt(testDirPath)
    }
    self.testDir = URL(fileURLWithPath: testDirPath, isDirectory: true)
    self.siltExecutable = URL(fileURLWithPath: siltExecutablePath)
  }

  /// Runs all the tests in the test directory and all its subdirectories.
  /// - returns: `true` if all tests passed.
  func run() throws -> Bool {
    let fm = FileManager.default
    let enumerator = fm.enumerator(at: testDir,
                                   includingPropertiesForKeys: nil)!
    var total = 0
    for case let file as URL in enumerator {
      guard file.pathExtension == "silt" else { continue }
      let dirPathLen = testDir.path.count
      var shortName = file.path
      if shortName.hasPrefix(testDir.path) {
        let shortEnd = shortName.index(shortName.startIndex,
                                       offsetBy: dirPathLen + 1)
        shortName = String(shortName[shortEnd..<shortName.endIndex])
      }
      let results = try run(file: file)
      total += results.count
      handleResults(results, shortName: shortName)
    }
    let testDesc = "test\(total == 1 ? "" : "s")"
    let passDesc = "pass\(passes == 1 ? "" : "es")"
    let failDesc = "failure\(failures == 1 ? "" : "s")"
    print("Executed \(total) \(testDesc) with \(passes) \(passDesc) " +
          "and \(failures) \(failDesc)")
    if failures == 0 {
      print("All tests passed! 🎉".green)
    }

    return failures == 0
  }

  func handleResults(_ results: [TestResult], shortName: String) {
    let allPassed = !results.contains { !$0.passed }
    if allPassed {
      print("\("✔".green.bold) \(shortName)")
    } else {
      print("\("𝗫".red.bold) \(shortName)")
    }
    for result in results {
      if result.passed {
        passes += 1
        print("  \("✔".green.bold) \(result.line.asString)")
      } else {
        failures += 1
        print("  \("𝗫".red.bold) \(result.line.asString)")
      }
    }
  }

  struct TestResult {
    let line: RunLine
    let passed: Bool
  }

  /// Runs
  private func run(file: URL) throws -> [TestResult] {
    let runLines = try RunLineParser.parseRunLines(in: file)
    var results = [TestResult]()
    for line in runLines {
      let process = Process()
      process.launchPath = siltExecutable.path
      process.arguments = line.arguments + [file.path]
      if line.command == .runNot {
        // Silence stderr when we're expecting a failure.
        process.standardError = Pipe()
      }
      process.launch()
      process.waitUntilExit()
      let passed = line.isFailure(process.terminationStatus)
      results.append(TestResult(line: line, passed: passed))
    }
    return results
  }
}
