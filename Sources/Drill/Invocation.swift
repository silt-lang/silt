/// Invocation.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Rainbow

import Lithosphere
import Crust
import Moho
import Mantle

extension Diagnostic.Message {
  static let noInputFiles = Diagnostic.Message(.error,
                                               "no input files provided")
}

public struct Invocation {
  public let options: Options
  public let sourceFiles: Set<String>

  public init(options: Options, paths: Set<String>) {
      self.options = options
      self.sourceFiles = paths
  }

  public typealias HadErrors = Bool

  public func run() throws -> HadErrors {
    let engine = DiagnosticEngine()
    let printingConsumer = PrintingDiagnosticConsumer(stream: &stderrStream)
    let printingConsumerToken = engine.register(printingConsumer)

    Rainbow.enabled = options.colorsEnabled

    if sourceFiles.isEmpty {
      engine.diagnose(.noInputFiles)
      return true
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
        let parser = Parser(diagnosticEngine: engine, tokens: layoutTokens)
        if let module = parser.parseTopLevelModule() {
          SyntaxDumper(stream: &stderrStream).dump(module)
        }
      case .dump(.scopes):
//        let layoutTokens = layout(tokens)
//        let parser = Parser(diagnosticEngine: engine, tokens: layoutTokens)
//        let module = parser.parseTopLevelModule()!
//        let binder = NameBinding(topLevel: module, engine: engine)
//        print(binder.performScopeCheck(topLevel: module))
        break
      case .verify(.parse):
        engine.unregister(printingConsumerToken)
        let layoutTokens = layout(tokens)
        let parser = Parser(diagnosticEngine: engine, tokens: layoutTokens)
        _ = parser.parseTopLevelModule()
        let verifier =
          DiagnosticVerifier(input: contents,
                             producedDiagnostics: engine.diagnostics)
        verifier.verify()
        return verifier.engine.hasErrors()
      }
    }
    return engine.hasErrors()
  }
}
