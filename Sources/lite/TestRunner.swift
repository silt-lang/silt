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

  func run() throws -> Bool {
    let fm = FileManager.default
    let enumerator = fm.enumerator(at: testDir,
                                   includingPropertiesForKeys: nil)!
    var allPassed = true
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
      allPassed = allPassed && passed
      if passed {
        print("\("✔".green) \(shortName)")
      } else {
        print("\("𝗫".red) \(shortName)")
      }
    }
    return !allPassed
  }

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
