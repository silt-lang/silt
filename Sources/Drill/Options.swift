/// Options.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Mantle

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

    /// Run the diagnostic verifier after parsing, scope checking and
    /// typechecking.
    case typecheck
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

    /// The compiler will lex, layout, parse, and scope check the source text
    /// then print the scopes to stdout.
    case scopes

    /// The compiler will lex, layout, parse, scope check, then type check
    /// the source text and dump the solving process.
    case typecheck

    /// The compiler will lex, layout, parse, scope check, type check, then
    /// lower the module to GraphIR.
    case girGen = "girgen"

    /// The compiler will lex, layout, parse, scope check, type check, lower
    /// to GIR, then lower the module to LLVM IR.
    case irGen = "irgen"

    /// The compiler will parse a GIR module then dump the parsed module.
    case parseGIR = "parse-gir"
  }
  case dump(DumpLayer)
  case verify(VerifyLayer)
  case compile
}

public class Options {
  public var mode: Mode = .compile
  public var colorsEnabled: Bool = false
  public var shouldPrintTiming: Bool = false
  public var inputURLs: [URL] = []
  public var typeCheckerDebugOptions: TypeCheckerDebugOptions = []

  // FIXME: There is duplication here between the layers.
  public init(
    mode: Mode = .compile,
    colorsEnabled: Bool = false,
    shouldPrintTiming: Bool = false,
    inputURLs: [URL],
    typeCheckerDebugOptions: TypeCheckerDebugOptions
  ) {
    self.mode = mode
    self.colorsEnabled = colorsEnabled
    self.shouldPrintTiming = shouldPrintTiming
    self.inputURLs = inputURLs
    self.typeCheckerDebugOptions = typeCheckerDebugOptions
  }
}
