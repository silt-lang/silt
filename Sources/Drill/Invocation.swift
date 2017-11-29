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

    let shineFile = Passes.lex |> Passes.shine
    let parseFile = shineFile |> Passes.parse
    let scopeCheckFile =
      parseFile |> Passes.scopeCheck

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
        run(Passes.lex |> Pass(name: "Describe Tokens") { tokens, _ in
          TokenDescriber.describe(tokens, to: &stdoutStream)
        })
      case .dump(.file):
        run(Passes.lex |> Pass(name: "Reprint File") { tokens, _ -> Void in
          for token in tokens {
            token.writeSourceText(to: &stdoutStream, includeImplicit: false)
          }
        })
      case .dump(.shined):
        run(shineFile |> Pass(name: "Dump Shined") { tokens, _ in
          for token in tokens {
            token.writeSourceText(to: &stdoutStream, includeImplicit: true)
          }
        })
      case .dump(.parse):
        run(parseFile |> Pass(name: "Dump Parsed") { module, _ in
          SyntaxDumper(stream: &stderrStream).dump(module)
        })
      case .dump(.scopes):
        run(scopeCheckFile |> Pass(name: "Dump Scopes") { module, _ in
          print(module)
        })
      case .verify(let verification):
        engine.unregister(printingConsumerToken)
        switch verification {
        case .parse:
          return run(makeVerifyPass(url: url, pass: parseFile,
                                    context: context)) ?? true
        case .scopes:
          return run(makeVerifyPass(url: url, pass: scopeCheckFile,
                                    context: context)) ?? true
        }
      }
    }
    return engine.hasErrors()
  }
}
