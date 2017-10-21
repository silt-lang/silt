/// Options.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// The mode the compiler will be executing in.
public enum Mode: String {
  /// The compiler will describe all the tokens in the source file, along with
  /// the leading and trailing trivia.
  case describeTokens = "describe-tokens"

  /// The compiler will reprint the source text as read from the token stream.
  case reprint

  /// The compiler will lex, layout, then parse the source text and dump the
  /// resulting AST.
  case dumpParse = "dump-parse"
}

public struct Options {
    public let mode: Mode
    public let colorsEnabled: Bool

    public init(mode: Mode, colorsEnabled: Bool) {
        self.mode = mode
        self.colorsEnabled = colorsEnabled
    }
}
