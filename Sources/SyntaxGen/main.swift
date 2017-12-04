/// main.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import CommandLine
import Foundation

extension OutputStream: TextOutputStream {
  public func write(_ string: String) {
    let data = string.data(using: .utf8)!
    _ = data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
      write(ptr, maxLength: data.count)
    }
  }
}

let cli = CLI()
let outputPath = StringOption(shortFlag: "o",
                              longFlag: "output-dir",
                              required: true,
                              helpMessage: "The output directory.")

cli.addOptions(outputPath)

do {
  try cli.parse()
} catch {
  cli.printUsage()
  exit(EXIT_FAILURE)
}

do {
  let generator = try SwiftGenerator(outputDir: outputPath.value!)
  generator.generate()
} catch {
  print("error: \(error)")
}
