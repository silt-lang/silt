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
func parseOptions() -> (Options, [String]) {
  let cli = CommandLineKit.CommandLine()
  let dumpOption =
    EnumOption<Mode.DumpKind>(longFlag: "dump", required: false,
      helpMessage: "Dumps the compiler's input at the specified stage in the " +
                   "compiler.")
  let disableColors =
    BoolOption(longFlag: "no-colors",
               helpMessage: "Disable ANSI colors in printed output.")
  cli.addOptions(dumpOption, disableColors)
  do {
    try cli.parse()
  } catch {
    cli.printUsage()
    exit(EXIT_FAILURE)
  }

  let mode: Mode
  if let dump = dumpOption.value {
    mode = .dump(dump)
  } else {
    mode = .compile
  }

  return (Options(mode: mode,
                  colorsEnabled: !disableColors.value), cli.unparsedArguments)
}

func main() throws {
  let (options, paths) = parseOptions()
  let invocation = Invocation(options: options, paths: paths)
  try invocation.run()
}

do {
  try main()
} catch {
  print("error: \(error)")
  exit(-1)
}
