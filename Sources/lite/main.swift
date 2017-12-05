/// main.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Drill
import Basic
import Utility
import LiteSupport
import Lithosphere
import Rainbow

#if os(Linux)
import Glibc
#endif

let cli = ArgumentParser(commandName: "lite", usage: "", overview: "")

let testDir =
  cli.add(option: "--test-dir", shortName: "-d",
          kind: String.self,
          usage: """
                 The top-level directory containing tests to run. \
                 Defaults to the current working directory.
                 """)

let siltExe =
  cli.add(option: "--silt", kind: String.self,
          usage: """
                 The path to the `silt` executable. \
                 Defaults to the executable next to `lite`.
                 """)

func run() -> Int32 {
  let args = Array(CommandLine.arguments.dropFirst())
  guard let result = try? cli.parse(args) else {
    cli.printUsage(on: Basic.stdoutStream)
    return EXIT_FAILURE
  }

  let engine = DiagnosticEngine()
  engine.register(PrintingDiagnosticConsumer(stream: &stderrStreamHandle))

  let siltExeURL =
    result.get(siltExe).map(URL.init(fileURLWithPath:)) ?? findSiltExecutable()

  guard let url = siltExeURL else {
    engine.diagnose(.init(.error, "unable to infer silt binary path"))
    return EXIT_FAILURE
  }

  var substitutions = [("silt", "\"\(url.path)\"")]

  if let filecheckURL = findFileCheckExecutable() {
    substitutions.append(("FileCheck", "\"\(filecheckURL.path)\""))
  }

  do {
    let allPassed = try runLite(substitutions: substitutions,
                                pathExtensions: ["silt"],
                                testDirPath: result.get(testDir),
                                testLinePrefix: "--")
    return allPassed ? EXIT_SUCCESS : EXIT_FAILURE
  } catch let err as LiteError {
    engine.diagnose(.init(.error, err.message))
    return EXIT_FAILURE
  } catch {
    engine.diagnose(.init(.error, "\(error)"))
    return EXIT_FAILURE
  }
}
exit(run())
