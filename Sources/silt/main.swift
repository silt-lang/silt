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
import CommandLineKit
import UpperCrust

/// The mode the compiler will be executing in.
enum Mode: String {
  /// The compiler will describe all the tokens in the source file, along with
  /// the leading and trailing trivia.
  case describeTokens = "describe-tokens"
}

func run(mode: Mode, paths: [String]) throws {
  switch mode {
  case .describeTokens:
    for path in paths {
      let url = URL(fileURLWithPath: path)
      let contents = try String(contentsOf: url, encoding: .utf8)
      let lexer = Lexer(input: contents, filePath: path)
      let tokens = lexer.tokenize()
      TokenDescriber.describe(tokens)
    }
  }
}

func main() throws {
  let cli = CommandLineKit.CommandLine()
  let modeOption =
    EnumOption<Mode>(longFlag: "mode",
                     required: true,
                     helpMessage: """
                     The mode in which to execute the compiler. This
                     """)
  cli.addOptions(modeOption)
  do {
    try cli.parse()
  } catch {
    cli.printUsage()
    exit(EXIT_FAILURE)
  }

  try run(mode: modeOption.value!, paths: cli.unparsedArguments)
}

do {
  try main()
} catch {
  print("error: \(error)")
  exit(-1)
}
