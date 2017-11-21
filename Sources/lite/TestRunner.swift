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
    var passes = [String]()
    var failures = [String]()
    let fm = FileManager.default
    let enumerator = fm.enumerator(at: testDir,
                                   includingPropertiesForKeys: nil)!
    for case let file as URL in enumerator {
      guard file.pathExtension == "silt" else { continue }
      let dirPathLen = testDir.path.count
      var shortName = file.path
      if shortName.hasPrefix(testDir.path) {
        let shortEnd = shortName.index(shortName.startIndex,
                                       offsetBy: dirPathLen + 1)
        shortName = String(shortName[shortEnd..<shortName.endIndex])
      }
      let passed = try run(file: file)
      if passed {
        passes.append(shortName)
        print("\("✔".green.bold) \(shortName)")
      } else {
        failures.append(shortName)
        print("\("𝗫".red.bold) \(shortName)")
      }
    }
    let passDesc = "pass\(passes.count == 1 ? "" : "es")"
    let failDesc = "failure\(failures.count == 1 ? "" : "s")"
    let total = passes.count + failures.count
    print("Executed \(total) tests with \(passes.count) \(passDesc) " +
          "and \(failures.count) \(failDesc)")
    if failures.isEmpty {
      print("All tests passed! 🎉".green)
    } else {
      print("Failures:")
      for failure in failures {
        print("  \("𝗫".red.bold) \(failure)")
      }
    }

    return failures.isEmpty
  }

  /// Runs
  private func run(file: URL) throws -> Bool {
    let runLines = try RunLineParser.parseRunLines(in: file)
    var allPassed = true
    for line in runLines {
      let process = Process()
      process.launchPath = siltExecutable.path
      process.arguments = line + [file.path]
      process.launch()
      process.waitUntilExit()
      allPassed = allPassed && process.terminationStatus == 0
    }
    return allPassed
  }
}
