/// Invocation.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Rainbow

import Lithosphere
import Crust
import Moho
import Mantle
import OuterCore
import InnerCore

extension Diagnostic.Message {
  static let noInputFiles = Diagnostic.Message(.error,
                                               "no input files provided")
}

extension Passes {
  // Create passes that perform the whole readFile->...->finalPass pipeline.
  static let lexFile = Passes.readFile |> Passes.lex
  static let shineFile = lexFile |> Passes.shine
  static let parseFile = shineFile |> Passes.parse
  static let scopeCheckFile = parseFile |> Passes.scopeCheck
  static let scopeCheckAsImport = parseFile |> Passes.scopeCheckImport
  static let typeCheckFile = scopeCheckFile |> Passes.typeCheck
}

public struct Invocation {
  public let options: Options

  public init(options: Options) {
    self.options = options
  }

  /// Clearly denotes a function as returning `true` if errors occurred.
  public typealias HadErrors = Bool

  /// Makes a pass that runs a provided pass and then performs diagnostic
  /// verification after it.
  /// - parameters:
  ///   - url: The URL of the file to read.
  ///   - pass: The pass to run before verifying.
  ///   - context: The context in which to run the pass.
  /// - note: The pass this function returns will never return `nil`, it will
  ///         return `true` if the verifier produced errors and `false`
  ///         otherwise. It is safe to force-unwrap.
  private func makeVerifyPass<PassTy: PassProtocol>(
    url: URL, pass: PassTy, context: PassContext
  ) -> Pass<PassTy.Input, HadErrors> {
    return Pass(name: "Diagnostic Verification") { input, ctx in
      _ = pass.run(input, in: ctx)
      let verifier =
        DiagnosticVerifier(url: url,
                           producedDiagnostics: ctx.engine.diagnostics)
      verifier.verify()
      return verifier.engine.hasErrors()
    }
  }

  public func run() -> HadErrors {
    let context = PassContext(options: options)
    let printingConsumer =
      PrintingDiagnosticConsumer(stream: &stderrStreamHandle)
    let printingConsumerToken = context.engine.register(printingConsumer)

    Rainbow.enabled = options.colorsEnabled

    // Force Rainbow to use ANSI colors even when not in a TTY.
    if Rainbow.outputTarget == .unknown {
      Rainbow.outputTarget = .console
    }

    if options.inputURLs.isEmpty {
      context.engine.diagnose(.noInputFiles)
      return true
    }

    defer {
      if options.shouldPrintTiming {
        context.timer.dump(to: &stdoutStreamHandle)
      }
    }

    // Create passes that perform the whole readFile->...->finalPass pipeline.
    let lexFile = Passes.readFile |> Passes.lex
    let shineFile = lexFile |> Passes.shine
    let parseFile = shineFile |> Passes.parse
    let parseGIRFile = lexFile |> Passes.parseGIR
    let scopeCheckFile = parseFile |> Passes.scopeCheck
    let typeCheckFile = scopeCheckFile |> Passes.typeCheck
    let girGenModule = typeCheckFile |> Passes.girGen
    let irGenModule = girGenModule |> Passes.irGen

    for url in options.inputURLs {
      func run<PassTy: PassProtocol>(_ pass: PassTy) -> PassTy.Output?
        where PassTy.Input == URL {
        return pass.run(url, in: context)
      }

      switch options.mode {
      case .compile:
        fatalError("only Parse is implemented")
      case .dump(.tokens):
        run(Passes.lexFile |> Pass(name: "Describe Tokens") { tokens, _ in
          TokenDescriber.describe(tokens, to: &stdoutStreamHandle)
        })
      case .dump(.file):
        run(Passes.lexFile |> Pass(name: "Reprint File") { tokens, _ -> Void in
          for token in tokens {
            token.writeSourceText(to: &stdoutStreamHandle,
                                  includeImplicit: false)
          }
        })
      case .dump(.shined):
        run(Passes.shineFile |> Pass(name: "Dump Shined") { tokens, _ in
          for token in tokens {
            token.writeSourceText(to: &stdoutStreamHandle,
                                  includeImplicit: true)
          }
        })
      case .dump(.parse):
        run(Passes.parseFile |> Pass(name: "Dump Parsed") { module, _ in
          SyntaxDumper(stream: &stderrStreamHandle).dump(module)
        })
      case .dump(.scopes):
        run(Passes.scopeCheckFile |> Pass(name: "Dump Scopes") { module, _ in
          print(module)
        })
      case .dump(.typecheck):
        run(Passes.typeCheckFile |> Pass(name: "Type Check") { module, _ in
          print(module)
        })
      case .dump(.girGen):
        run(girGenModule |> Pass(name: "Dump Generated GIR") { module, _ in
          module.dump()
        })
      case .dump(.parseGIR):
        run(parseGIRFile |> Pass(name: "Dump Parsed GIR") { module, _ in
          module.dump()
        })
      case .dump(.irGen):
        run(irGenModule |> Pass(name: "Dump LLVM IR") { module, _ in
          module.dump()
        })
      case .verify(let verification):
        context.engine.unregister(printingConsumerToken)
        switch verification {
        case .parse:
          return run(makeVerifyPass(url: url, pass: Passes.parseFile,
                                    context: context))!
        case .scopes:
          return run(makeVerifyPass(url: url, pass: Passes.scopeCheckFile,
                                    context: context))!
        case .typecheck:
          return run(makeVerifyPass(url: url, pass: typeCheckFile,
                                    context: context))!
        }
      }
    }
    return context.engine.hasErrors()
  }
}
