/// main.swift
///
/// Copyright 2017-2018, The Silt Language Project.
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

let runSerial =
  cli.add(option: "--no-parallel", kind: Bool.self,
          usage: "Don't run tests in parallel.")

let filterRegexes =
  cli.add(option: "--filter", kind: [String].self, strategy: .oneByOne,
          usage: """
                 A list of regexes to filter the test files. If a test matches
                 any of the provided filters, it's included in the test run.
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

  let isParallel = !(result.get(runSerial) ?? false)
  let parallelismLevel: ParallelismLevel = isParallel ? .automatic : .none

  do {
    let regexStrings = result.get(filterRegexes) ?? []
    let regexes = try regexStrings.map {
      try NSRegularExpression(pattern: $0)
    }
    let allPassed = try runLite(substitutions: substitutions,
                                pathExtensions: ["silt", "gir"],
                                testDirPath: result.get(testDir),
                                testLinePrefix: "--",
                                parallelismLevel: parallelismLevel,
                                filters: regexes)
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
