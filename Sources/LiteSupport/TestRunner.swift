/// TestRunner.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere
import SwiftShell

#if os(Linux)
/// HACK: This is needed because on macOS, ObjCBool is a distinct type
///       from Bool. On Linux, however, it is a typealias.
extension ObjCBool {
  /// Converts the ObjCBool value to a Swift Bool.
  var boolValue: Bool { return self }
}
#endif


/// TestRunner is responsible for coordinating a set of tests, running them, and
/// reporting successes and failures.
class TestRunner {
  /// The test directory in which tests reside.
  let testDir: URL

  /// The URL of the silt executable.
  let siltExecutable: URL

  /// Creates a test runner that will execute all tests in the provided
  /// directory using the provided `silt` executable.
  /// - throws: An error if the test directory or executable are invalid.
  init(testDirPath: String?, siltExecutablePath: String?) throws {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    let testDirPath = testDirPath ?? FileManager.default.currentDirectoryPath
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

  func discoverTests() throws -> [TestFile] {
    let fm = FileManager.default
    let enumerator = fm.enumerator(at: testDir,
                                   includingPropertiesForKeys: nil)!
    var files = [TestFile]()
    for case let file as URL in enumerator {
      guard file.pathExtension == "silt" else { continue }
      let runLines = try RunLineParser.parseRunLines(in: file)
      if runLines.isEmpty { continue }
      files.append(TestFile(url: file, runLines: runLines))
    }
    return files
  }

  /// Runs all the tests in the test directory and all its subdirectories.
  /// - returns: `true` if all tests passed.
  func run() throws -> Bool {
    let files = try discoverTests()
    if files.isEmpty { return true }

    var resultMap = [URL: [TestResult]]()
    for file in files {
      resultMap[file.url] = try run(file: file)
    }

    return handleResults(files: files, resultMap)
  }

  /// Prints individual test results for one specific file.
  func handleResults(files: [TestFile], _ map: [URL: [TestResult]]) -> Bool {
    let commonPrefix = files.map { $0.url.path }.commonPrefix
    let prefixLen = commonPrefix.count
    var passes = 0
    var failures = 0
    print("Running all tests in \(commonPrefix.bold)")
    for file in files {
      guard let results = map[file.url] else { continue }
      handleResults(file, results: results, prefixLen: prefixLen,
                    passes: &passes, failures: &failures)
    }

    let total = passes + failures
    let testDesc = "\(total) test\(total == 1 ? "" : "s")".bold
    let passDesc = "\(passes) pass\(passes == 1 ? "" : "es")".green.bold
    let failDesc = "\(failures) failure\(failures == 1 ? "" : "s")".red.bold
    print("Executed \(testDesc) with \(passDesc) and \(failDesc)")

    if failures == 0 {
      print("All tests passed! 🎉".green.bold)
      return true
    }

    return false
  }

  func handleResults(_ file: TestFile, results: [TestResult],
                     prefixLen: Int, passes: inout Int,
                     failures: inout Int) {
    let path = file.url.path
    let suffixIdx = path.index(path.startIndex, offsetBy: prefixLen,
                               limitedBy: path.endIndex)
    let shortName = suffixIdx.map { path.suffix(from: $0) } ?? Substring(path)
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
        if !result.output.stderror.isEmpty {
          print("    stderr:")
          let lines = result.output.stderror.split(separator: "\n")
                                            .joined(separator: "\n      ")
          print("      \(lines)")
        }
        if !result.output.stdout.isEmpty {
          print("    stdout:")
          let lines = result.output.stdout.split(separator: "\n")
                                          .joined(separator: "\n      ")
          print("      \(lines)")
        }
        print("    command line:")
        print("      \(result.makeCommandLine(siltExecutable))")
      }
    }
  }

  /// Runs all the run lines in a given file and returns a test result
  /// with the individual successes or failures.
  private func run(file: TestFile) throws -> [TestResult] {
    var results = [TestResult]()
    for line in file.runLines {
      let output = SwiftShell.main.run(siltExecutable.path,
                                       line.arguments + [file.url.path])
      let passed = line.isFailure(output.exitcode)
      results.append(TestResult(line: line, passed: passed,
                                output: output, file: file.url))
    }
    return results
  }
}
