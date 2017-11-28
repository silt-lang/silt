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

  private func makeVerifyPass<PassTy: PassProtocol>(
    url: URL, pass: PassTy, context: PassContext) -> Pass<PassTy.Input, Bool> {
    return Pass(name: "Diagnostic Verification") { input, ctx in
      _ = pass.run(input, in: ctx)
      let verifier =
        DiagnosticVerifier(url: url,
                           producedDiagnostics: ctx.engine.diagnostics)
      verifier.verify()
      return verifier.engine.hasErrors()
    }
  }

  public func run() throws -> HadErrors {
    let engine = DiagnosticEngine()
    let printingConsumer = PrintingDiagnosticConsumer(stream: &stderrStream)
    let printingConsumerToken = engine.register(printingConsumer)

    Rainbow.enabled = options.colorsEnabled

    // Force Rainbow to use ANSI colors even when not in a TTY.
    if Rainbow.outputTarget == .unknown {
      Rainbow.outputTarget = .console
    }

    if sourceFiles.isEmpty {
      engine.diagnose(.noInputFiles)
      return true
    }

    let context = PassContext(engine: engine)

    defer {
      if options.shouldPrintTiming {
        context.timer.dump(to: &stdoutStream)
      }
    }

    let lexerPass = Pass<URL, [TokenSyntax]>(name: "Lex") { url, ctx in
      do {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lexer = Lexer(input: contents, filePath: url.path)
        return lexer.tokenize()
      } catch {
        ctx.engine.diagnose(.couldNotReadInput(url))
        return nil
      }
    }

    let shinePass = lexerPass |> Pass(name: "Shine") { tokens, ctx in
      layout(tokens)
    }

    let parsePass =
      shinePass |> Pass(name: "Parse") { tokens, ctx -> ModuleDeclSyntax? in
        let parser = Parser(diagnosticEngine: ctx.engine, tokens: tokens)
        return parser.parseTopLevelModule()
      }

    let scopeCheckPass =
      parsePass |> Pass(name: "Scope Check") { module, ctx -> DeclaredModule? in
        let binder = NameBinding(topLevel: module, engine: ctx.engine)
        return binder.performScopeCheck(topLevel: module)
      }

    for path in sourceFiles {
      let url = URL(fileURLWithPath: path)

      func run<PassTy: PassProtocol>(_ pass: PassTy) -> PassTy.Output?
        where PassTy.Input == URL {
          return pass.run(url, in: context)
      }

      switch options.mode {
      case .compile:
        fatalError("only Parse is implemented")
      case .dump(.tokens):
        run(lexerPass |> Pass(name: "Describe Tokens") { tokens, _ in
          TokenDescriber.describe(tokens, to: &stdoutStream)
        })
      case .dump(.file):
        run(lexerPass |> Pass(name: "Reprint File") { tokens, _ in
          for token in tokens {
            token.writeSourceText(to: &stdoutStream, includeImplicit: false)
          }
        })
      case .dump(.shined):
        run(shinePass |> Pass(name: "Dump Shined") { tokens, _ in
          for token in tokens {
            token.writeSourceText(to: &stdoutStream, includeImplicit: true)
          }
        })
      case .dump(.parse):
        run(parsePass |> Pass(name: "Dump Parsed") { module, _ in
          SyntaxDumper(stream: &stderrStream).dump(module)
        })
      case .dump(.scopes):
        let layoutTokens = layout(tokens)
        let parser = Parser(diagnosticEngine: engine, tokens: layoutTokens)
        let module = parser.parseTopLevelModule()!
        let binder = NameBinding(topLevel: module, engine: engine)
        print(binder.performScopeCheck(topLevel: module))
      case .verify(let verification):
        engine.unregister(printingConsumerToken)
        switch verification {
        case .parse:
          return run(makeVerifyPass(url: url, pass: parsePass,
                                    context: context))
        case .scopes:
          return run(makeVerifyPass(url: url, pass: scopeCheckPass,
                                    context: context))
        }
      }
    }
    return engine.hasErrors()
  }
}
