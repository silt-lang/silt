/// Options.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// A distinct layer of compilation that defines places where the diagnostic
/// verifier can work.
public enum VerifyLayer: String {
  /// Run the diagnostic verifier after parsing but before scope checking.
  case parse

  /// Run the diagnostic verifier after parsing and scope checking but before
  /// typechecking.
  case scopes
}

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

    case scopes
  }
  case dump(DumpKind)
  case verify(VerifyLayer)
  case compile
}

public struct Options {
  public let mode: Mode
  public let colorsEnabled: Bool
  public let shouldPrintTiming: Bool

  public init(mode: Mode, colorsEnabled: Bool, shouldPrintTiming: Bool) {
    self.mode = mode
    self.colorsEnabled = colorsEnabled
    self.shouldPrintTiming = shouldPrintTiming
  }
}
