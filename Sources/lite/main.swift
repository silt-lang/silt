/// main.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import CommandLineKit
import Drill
import Lithosphere

/// The main entry point for `lite`.
func main() -> Int {
  let testDir =
    StringOption(longFlag: "test-dir",
                 required: true,
      helpMessage: "The top-level directory containing tests to run")

  let siltExe = StringOption(longFlag: "silt",
                             required: true,
                             helpMessage: "The path to the `silt` executable")

  let cli = CommandLineKit.CommandLine()
  cli.addOptions(testDir, siltExe)

  do {
    try cli.parse()
  } catch {
    cli.printUsage()
    exit(-1)
  }

  let engine = DiagnosticEngine()
  engine.register(PrintingDiagnosticConsumer(stream: &stderrStream))

  do {
    let testRunner = try TestRunner(testDirPath: testDir.value!,
                                    siltExecutablePath: siltExe.value!)
    return try testRunner.run() ? -1 : 0
  } catch {
    if let err = error as? Diagnostic.Message {
      engine.diagnose(err)
    } else {
/// HACK: Error metadata is still broken on Linux.
#if os(macOS)
      fatalError("unhandled error: \(error)")
#endif
    }
    return -1
  }
}

exit(Int32(main()))
