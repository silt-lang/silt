/// main.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

import Foundation
import Drill
import CommandLineKit


/// Parses the command-line options into an Options struct and a list of file
/// paths.
func parseOptions() -> (Options, Set<String>) {
  let cli = CommandLineKit.CommandLine()
  let dumpOption =
    EnumOption<Mode.DumpKind>(longFlag: "dump", required: false,
                              helpMessage:
        "Dumps the compiler's input at the specified stage in the compiler.")
  let verify =
    EnumOption<VerifyLayer>(longFlag: "verify",
      helpMessage: "Run the compiler in diagnostic verifier mode.")
  let disableColors =
    BoolOption(longFlag: "no-colors",
               helpMessage: "Disable ANSI colors in printed output.")
  cli.addOptions(dumpOption, verify, disableColors)

  do {
    try cli.parse()
  } catch {
    cli.printUsage()
    exit(EXIT_FAILURE)
  }

  let mode: Mode
  if let layer = verify.value {
    mode = .verify(layer)
  } else if let dump = dumpOption.value {
    mode = .dump(dump)
  } else {
    mode = .compile
  }

  return (Options(mode: mode,
                  colorsEnabled: !disableColors.value),
          Set(cli.unparsedArguments))
}

func main() throws -> Int {
  let (options, paths) = parseOptions()
  let invocation = Invocation(options: options, paths: paths)
  return try invocation.run() ? -1 : 0
}

do {
  exit(Int32(try main()))
} catch {
  print("error: \(error)")
  exit(-1)
}
