/// SiltInvocation.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Symbolic

/// Finds the silt executable relative to the location of the `lite` executable.
func findSiltExecutable() -> URL? {
  guard let path = SymbolInfo(address: #dsohandle)?.filename else { return nil }
  let siltURL = path.deletingLastPathComponent()
                    .appendingPathComponent("silt")
  guard FileManager.default.fileExists(atPath: siltURL.path) else { return nil }
  return siltURL
}
