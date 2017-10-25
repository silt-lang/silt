/// Invocation.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere
import Rainbow
import Crust

extension Diagnostic.Message {
  static let noInputFiles = Diagnostic.Message(.error,
                                               "no input files provided")
}

public struct Invocation {
  public let options: Options
  public let sourceFiles: [String]

  public init(options: Options, paths: [String]) {
    self.options = options
    self.sourceFiles = paths
  }

  public func run() throws {
    let engine = DiagnosticEngine()
    let consumer = PrintingDiagnosticConsumer(stream: &stderrStream)
    engine.register(consumer)

    Rainbow.enabled = options.colorsEnabled

    if sourceFiles.isEmpty {
      engine.diagnose(.noInputFiles)
      return
    }

    for path in sourceFiles {
      let url = URL(fileURLWithPath: path)
      let contents = try String(contentsOf: url, encoding: .utf8)
      let lexer = Lexer(input: contents, filePath: path)
      let tokens = lexer.tokenize()
      switch options.mode {
      case .compile:
        fatalError("only Parse is implemented")
      case .dump(.tokens):
        TokenDescriber.describe(tokens, to: &stdoutStream)
      case .dump(.file):
        for token in tokens {
          token.writeSourceText(to: &stdoutStream, includeImplicit: false)
        }
      case .dump(.shined):
        let layoutTokens = layout(tokens)
        for token in layoutTokens {
          token.writeSourceText(to: &stdoutStream, includeImplicit: true)
        }
      case .dump(.parse):
        let layoutTokens = layout(tokens)
        let parser = Parser(tokens: layoutTokens)
        SyntaxDumper(stream: &stderrStream).dump(parser.parseTopLevelModule()!)
      }
    }
  }
}
