/// DiagnosticMessage+lite.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

/// Extra diagnostic messages that `lite` might throw.
extension Diagnostic.Message {
  /// The test directory could not be found on the file system.
  static func couldNotOpenTestDir(_ path: String) -> Diagnostic.Message {
    return .init(.error, "could not open test directory at '\(path)'")
  }

  /// The test directory is not actually a directory.
  static func testDirIsNotDirectory(_ path: String) -> Diagnostic.Message {
    return .init(.error, "'\(path)' is not a directory")
  }

  /// We couldn't find the silt executable provided.
  static func couldNotFindSilt(_ path: String) -> Diagnostic.Message {
    return .init(.error, "could not find silt binary at '\(path)'")
  }

  /// We weren't able to execute the silt executable provided.
  static func couldNotExecuteSilt(_ path: String) -> Diagnostic.Message {
    return .init(.error, "could not execute silt binary at '\(path)'")
  }
}
