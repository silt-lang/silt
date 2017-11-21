/// DiagnosticMessage+lite.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

extension Diagnostic.Message {
  static func couldNotOpenTestDir(_ path: String) -> Diagnostic.Message {
    return .init(.error, "could not open test directory at '\(path)'")
  }
  static func testDirIsNotDirectory(_ path: String) -> Diagnostic.Message {
    return .init(.error, "'\(path)' is not a directory")
  }
  static func couldNotFindSilt(_ path: String) -> Diagnostic.Message {
    return .init(.error, "could not find silt binary at '\(path)'")
  }
  static func couldNotExecuteSilt(_ path: String) -> Diagnostic.Message {
    return .init(.error, "could not execute silt binary at '\(path)'")
  }
}
