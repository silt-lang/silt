/// FileCheck+Diagnostics.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

extension Diagnostic.Message {
    static let requiresOneCheckFile =
        Diagnostic.Message(.error, "file-check requires a single CHECK file")

    static func couldNotOpenFile(_ file: String) -> Diagnostic.Message {
        return .init(.error, "could not open input file '\(file)'")
    }
}
