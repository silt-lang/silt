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

/// Represents a test that either passed or failed, and contains the run line
/// that triggered the result.
struct TestResult {
  /// The run line comprising this test.
  let line: RunLine

  /// Whether this test passed or failed.
  let passed: Bool
}


/// TestRunner is responsible for coordinating a set of tests, running them, and
/// reporting successes and failures.
class TestRunner {
  /// The number of run lines that passed in all files.
  private var passes = 0

  /// The number of run lines that failed in all files.
  private var failures = 0

  /// The test directory in which tests reside.
  let testDir: URL

  /// The URL of the silt executable.
  let siltExecutable: URL

  /// Creates a test runner that will execute all tests in the provided
  /// directory using the provided `silt` executable.
  /// - throws: An error if the test directory or executable are invalid.
  init(testDirPath: String, siltExecutablePath: String?) throws {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: testDirPath, isDirectory: &isDir) else {
      throw Diagnostic.Message.couldNotOpenTestDir(testDirPath)
    }
    guard isDir.boolValue else {
      throw Diagnostic.Message.testDirIsNotDirectory(testDirPath)
    }
    self.testDir = URL(fileURLWithPath: testDirPath, isDirectory: true)

    if let siltPath = siltExecutablePath {
      guard fm.fileExists(atPath: siltPath) else {
        throw Diagnostic.Message.couldNotFindSilt(siltPath)
      }
      self.siltExecutable = URL(fileURLWithPath: siltPath)
    } else {
      guard let siltURL = findSiltExecutable() else {
        throw Diagnostic.Message.couldNotInferSilt
      }
      self.siltExecutable = siltURL
    }
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
    let testDesc = "\(total) test\(total == 1 ? "" : "s")".bold
    let passDesc = "\(passes) pass\(passes == 1 ? "" : "es")".green.bold
    let failDesc = "\(failures) failure\(failures == 1 ? "" : "s")".red.bold
    print("Executed \(testDesc) with \(passDesc) and \(failDesc)")

    if failures == 0 {
      print("All tests passed! 🎉".green.bold)
    }

    return failures == 0
  }

  /// Prints individual test results for one specific file.
  func handleResults(_ results: [TestResult], shortName: String) {
    if results.isEmpty { return }
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

  /// Runs all the run lines in a given file and returns a test result
  /// with the individual successes or failures.
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
