/// FileHandle+TextOutputStream.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        write(string.data(using: .utf8)!)
    }
}

public var stderrStream = FileHandle.standardError
public var stdoutStream = FileHandle.standardOutput

