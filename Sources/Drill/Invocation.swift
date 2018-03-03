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

extension Diagnostic.Message {
  static let noInputFiles = Diagnostic.Message(.error,
                                               "no input files provided")
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

    if options.inputPaths.isEmpty {
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

    for path in options.inputPaths {
      let url = URL(fileURLWithPath: path)

      func run<PassTy: PassProtocol>(_ pass: PassTy) -> PassTy.Output?
        where PassTy.Input == URL {
        return pass.run(url, in: context)
      }

      switch options.mode {
      case .compile:
        fatalError("only Parse is implemented")
      case .dump(.tokens):
        run(lexFile |> Pass(name: "Describe Tokens") { tokens, _ in
          TokenDescriber.describe(tokens, to: &stdoutStreamHandle)
        })
      case .dump(.file):
        run(lexFile |> Pass(name: "Reprint File") { tokens, _ -> Void in
          for token in tokens {
            token.writeSourceText(to: &stdoutStreamHandle,
                                  includeImplicit: false)
          }
        })
      case .dump(.shined):
        run(shineFile |> Pass(name: "Dump Shined") { tokens, _ in
          for token in tokens {
            token.writeSourceText(to: &stdoutStreamHandle,
                                  includeImplicit: true)
          }
        })
      case .dump(.parse):
        run(parseFile |> Pass(name: "Dump Parsed") { module, _ in
          SyntaxDumper(stream: &stderrStreamHandle).dump(module)
        })
      case .dump(.scopes):
        run(scopeCheckFile |> Pass(name: "Dump Scopes") { module, _ in
          print(module)
        })
      case .dump(.typecheck):
        run(typeCheckFile |> Pass(name: "Type Check") { module, _ in
          print(module)
        })
      case .dump(.parseGIR):
        run(parseGIRFile |> Pass(name: "Dump Parsed GIR") { module, _ in
          module.dump()
        })
      case .dump(.gir):
        run(Pass(name: "Dump GIR") { module, _ in
          let module = GIRModule(name: "main")
          let builder = IRBuilder(module: module)
          let natType = module.dataType(name: "Nat") { nat in
            nat.addConstructor(name: "Z",
                               type: module.functionType(arguments: [],
                                                         returnType: nat))
            nat.addConstructor(name: "S",
                               type: module.functionType(arguments: [nat],
                                                         returnType: nat))
          }
          let listType = module.dataType(name: "List") {
            $0.addParameter(name: "A", type: module.typeType)
            let aArch = $0.archetype(at: 0)
            let subst = $0.substituted([
              aArch: $0.archetype(at: 0)
            ])
            $0.addConstructor(name: "[]",
                              type: module.functionType(arguments: [],
                                                        returnType: subst))
            $0.addConstructor(name: "_::_",
                              type: module.functionType(arguments: [aArch],
                                                        returnType: subst))
          }
          let personRec = module.recordType(name: "Person") {
            $0.addField(name: "age", type: natType)
          }
          let listPersonType = listType.substituted([
            listType.archetype(at: 0): personRec
          ])
          let continuationTy =
            module.functionType(arguments: [], returnType: module.bottomType)
          let a = builder.buildContinuation(name: "main")
          let x = a.appendParameter(type: listPersonType)
          let y = a.appendParameter(type: listPersonType)
          let ret = a.appendParameter(type: continuationTy, name: "re,t")
          let b = builder.buildContinuation(name: "sub.1")
          b.appendParameter(type: listPersonType)
          b.appendParameter(type: listPersonType, ownership: .borrowed)
          let bRet = b.appendParameter(type: continuationTy, name: "ret")
          IRVerifier(module: module).verify()
          let writer = IRWriter(stream: &stdoutStreamHandle)
          writer.write(module)
        })
      case .verify(let verification):
        context.engine.unregister(printingConsumerToken)
        switch verification {
        case .parse:
          return run(makeVerifyPass(url: url, pass: parseFile,
                                    context: context))!
        case .scopes:
          return run(makeVerifyPass(url: url, pass: scopeCheckFile,
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
