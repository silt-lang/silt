/// main.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Drill
import CommandLine
import LiteSupport
import Lithosphere
import Rainbow

#if os(Linux)
import Glibc
#endif

func run() -> Int {
  let testDir =
    StringOption(shortFlag: "d",
      longFlag: "test-dir",
      helpMessage: "The top-level directory containing tests to run. " +
                   "Defaults to the current working directory.")

  let siltExe = StringOption(longFlag: "silt",
    helpMessage: "The path to the `silt` executable. " +
                 "Defaults to the executable next to `lite`.")

  let cli = CLI()
  cli.addOptions(testDir, siltExe)

  do {
    try cli.parse()
  } catch {
    cli.printUsage()
    return -1
  }

  let engine = DiagnosticEngine()
  engine.register(PrintingDiagnosticConsumer(stream: &stderrStream))

  let siltExeURL =
    siltExe.value.map(URL.init(fileURLWithPath:)) ?? findSiltExecutable()

  guard let url = siltExeURL else {
    engine.diagnose(.init(.error, "unable to infer silt binary path"))
    return -1
  }

  var substitutions = [("silt", url.path.quoted)]

  if let filecheckURL = findFileCheckExecutable() {
    substitutions.append(("FileCheck", filecheckURL.path.quoted))
  }

  do {
    let allPassed = try runLite(substitutions: substitutions,
                                pathExtensions: ["silt"],
                                testDirPath: testDir.value,
                                testLinePrefix: "--")
    return allPassed ? 0 : -1
  } catch let err as LiteError {
    engine.diagnose(.init(.error, err.message))
    return -1
  } catch {
    engine.diagnose(.init(.error, "\(error)"))
    return -1
  }
}

exit(Int32(run()))
