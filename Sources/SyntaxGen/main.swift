/// main.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Basic
import Utility
import Foundation

extension OutputStream: TextOutputStream {
  public func write(_ string: String) {
    let data = string.data(using: .utf8)!
    _ = data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
      write(ptr, maxLength: data.count)
    }
  }
}

let cli = ArgumentParser(usage: "SyntaxGen", overview: "")
let outputDir = cli.add(option: "--output-dir", shortName: "-o",
                        kind: String.self)

let args = Array(CommandLine.arguments.dropFirst())
guard let result = try? cli.parse(args) else {
  cli.printUsage(on: Basic.stdoutStream)
  exit(EXIT_FAILURE)
}

guard let outputPath = result.get(outputDir) else {
  cli.printUsage(on: Basic.stdoutStream)
  exit(EXIT_FAILURE)
}

let generator = try SwiftGenerator(outputDir: outputPath)
generator.generate()
