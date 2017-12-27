/// Options.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// The mode the compiler will be executing in.
public enum Mode {
  /// A distinct layer of compilation that defines places where the diagnostic
  /// verifier can work.
  public enum VerifyLayer: String {
    /// Run the diagnostic verifier after parsing but before scope checking.
    case parse

    /// Run the diagnostic verifier after parsing and scope checking but before
    /// typechecking.
    case scopes
  }

  public enum DumpLayer: String {
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

    /// The compiler will lex, layout, parse, scope check, then type check
    /// the source text and dump the solving process.
    case typecheck
  }
  case dump(DumpLayer)
  case verify(VerifyLayer)
  case compile
}

public class Options {
  public var mode: Mode = .compile
  public var colorsEnabled: Bool = true
  public var shouldPrintTiming: Bool = false
  public var inputPaths: Set<String> = []

  public init() {}
}
