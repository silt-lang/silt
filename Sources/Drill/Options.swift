/// Options.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// The mode the compiler will be executing in.
public enum Mode {
  public enum DumpKind: String {
    /// The compiler will describe all the tokens in the source file, along with
    /// the leading and trailing trivia.
    case tokens

    /// The compiler will lex, layout, then parse the source text and dump the
    /// resulting AST.
    case parse

    /// The compiler will lex, layout, then parse the source text and print the
    /// original file from the token stream.
    case file

    /// The compiler will lex, layout, then parse the source text and print the
    /// file from the token stream including implicit scope marking tokens.
    case shined
  }
  case dump(DumpKind)
  case compile
}

public struct Options {
    public let mode: Mode
    public let colorsEnabled: Bool

    public init(mode: Mode, colorsEnabled: Bool) {
        self.mode = mode
        self.colorsEnabled = colorsEnabled
    }
}
