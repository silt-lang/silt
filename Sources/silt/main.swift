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
import Utility
import Basic

extension Mode.VerifyLayer: StringEnumArgument {
  public static var completion: ShellCompletion {
    return ShellCompletion.values([
      ("parse", "Verify the result of parsing the input file(s)"),
      ("scopes", "Verify the result of scope checking the input file(s)"),
    ])
  }
}

extension Mode.DumpLayer: StringEnumArgument {
  public static var completion: ShellCompletion {
    return ShellCompletion.values([
      (Mode.DumpLayer.tokens.rawValue,
          "Dump the result of tokenizing the input file(s)"),
      (Mode.DumpLayer.parse.rawValue,
          "Dump the result of parsing the input file(s)"),
      (Mode.DumpLayer.file.rawValue,
          "Dump the result of parsing and reconstructing the input file(s)"),
      (Mode.DumpLayer.shined.rawValue,
          "Dump the result of shining the input file(s)"),
      (Mode.DumpLayer.scopes.rawValue,
          "Dump the result of scope checking the input file(s)"),
    ])
  }
}


/// Parses the command-line options into an Options struct and a list of file
/// paths.
func parseOptions() -> Options {
  let cli = ArgumentParser(commandName: "silt",
                           usage: "[options] <input file(s)>",
                           overview: "The Silt compiler frontend")
  let binder = ArgumentBinder<Options>()

  binder.bind(
    option: cli.add(
      option: "--dump",
      kind: Mode.DumpLayer.self,
      usage: "Dump the result of compiling up to a given layer"),
    to: { opt, r in opt.mode = .dump(r) })
  binder.bind(
    option: cli.add(
      option: "--verify",
      kind: Mode.VerifyLayer.self,
      usage: "Verify the result of compiling up to a given layer"),
    to: { opt, r in opt.mode = .verify(r) })
  binder.bind(
    option: cli.add(option: "--no-colors", kind: Bool.self),
    to: { opt, r in opt.colorsEnabled = !r })
  binder.bind(
    option: cli.add(option: "--debug-print-timing", kind: Bool.self),
    to: { opt, r in opt.shouldPrintTiming = r })
  binder.bindArray(
    positional: cli.add(
      positional: "",
      kind: [String].self,
      usage: "One or more input file(s)",
      completion: .filename),
    to: { opt, fs in opt.inputPaths.formUnion(fs) })

  let args = Array(CommandLine.arguments.dropFirst())
  guard let result = try? cli.parse(args) else {
    cli.printUsage(on: Basic.stdoutStream)
    exit(EXIT_FAILURE)
  }
  var options = Options()
  binder.fill(result, into: &options)
  return options
}

func main() -> Int32 {
  let invocation = Invocation(options: parseOptions())
  return invocation.run() ? -1 : 0
}

exit(main())
