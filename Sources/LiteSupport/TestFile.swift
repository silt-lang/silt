/// TestFile.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import SwiftShell

/// Represents a test that either passed or failed, and contains the run line
/// that triggered the result.
struct TestResult {
  /// The run line comprising this test.
  let line: RunLine

  /// Whether this test passed or failed.
  let passed: Bool

  /// The output from running this test.
  let output: RunOutput

  /// The file being executed
  let file: URL

  /// Creates a reproducible command to execute this test.
  func makeCommandLine(_ siltExe: URL) -> String {
    return ([siltExe.path, file.path] + line.arguments).joined(separator: " ")
  }
}

/// Represents a file containing at least one `lite` run line.
struct TestFile {
  /// The URL of the file on disk.
  let url: URL

  /// The set of run lines in this file.
  let runLines: [RunLine]
}
