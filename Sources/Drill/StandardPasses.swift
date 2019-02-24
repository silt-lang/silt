//
//  StandardPasses.swift
//  Drill
//
//  Created by Harlan Haskins on 11/28/17.
//

import Foundation
import Lithosphere
import Crust
import LLVM
import Moho
import Mantle
import Seismography
import Mesosphere
import OuterCore
import InnerCore

private func processImportedFile(_ modPath: URL) -> LocalNames? {
  let options = Options(mode: .dump(.typecheck),
                        colorsEnabled: false,
                        shouldPrintTiming: false,
                        inputURLs: [modPath],
                        typeCheckerDebugOptions: [])
  let context = PassContext(options: options)
  let pipeline = (Passes.parseFile |> Passes.scopeCheckImport)
  let result = pipeline.run(modPath, in: context)
  guard let (declModule, locals) = result else {
    return nil
  }
  guard Passes.typeCheck.run(declModule, in: context) != nil else {
    return nil
  }
  return locals
}

enum Passes {
  /// Reads a file and returns both the String contents of the file and
  /// the URL of the file.
  static let readFile =
    Pass<URL, (String, URL)>(name: "Read File") { url, ctx in
      do {
        return (try String(contentsOf: url, encoding: .utf8), url)
      } catch {
        ctx.engine.diagnose(.couldNotReadInput(url))
        return nil
      }
    }

  /// The Lex pass reads a URL from the file system and tokenizes it into a
  /// stream of TokenSyntax nodes.
  static let lex =
    Pass<(String, URL), [TokenSyntax]>(name: "Lex") { file, ctx in
      let lexer = Lexer(input: file.0, filePath: file.1.path)
      let tokens = lexer.tokenize()

      let tree = SyntaxFactory.makeSourceFileSyntax(tokens)
      let converter = SourceLocationConverter(file: file.1.path,
                                              tree: tree)
      ctx.currentConverter = converter

      ctx.engine.forEachConsumer { consumer in
        if let printingConsumer = consumer as? DelayedDiagnosticConsumer {
          printingConsumer.attachAndDrain(converter)
        }
      }
      return tokens
    }

  /// The Shine pass takes a token stream and adds additional implicit tokens
  /// representing the beginning and ends of scopes.
  static let shine =
    Pass<[TokenSyntax], [TokenSyntax]>(name: "Shine") { tokens, _ in
      layout(tokens)
    }

  /// The Parse pass runs the parser over a Shined token stream and produces a
  /// full-fledged Syntax tree.
  static let parse =
    Pass<[TokenSyntax], ModuleDeclSyntax>(name: "Parse") { tokens, ctx in
      let parser = Parser(diagnosticEngine: ctx.engine, tokens: tokens,
                          converter: ctx.currentConverter!)
      return parser.parseTopLevelModule()
    }

  static let parseGIR =
    Pass<[TokenSyntax], GIRModule>(name: "Parse GIR") { tokens, ctx in
      let parser = Parser(diagnosticEngine: ctx.engine, tokens: tokens,
                          converter: ctx.currentConverter!)
      let girparser = GIRParser(parser)
      return girparser.parseTopLevelModule()
    }

  /// The ScopeCheck pass ensures the program is well-scoped and doesn't use
  /// unreachable variables.
  static let scopeCheck =
    DiagnosticGatePass(
      Pass<ModuleDeclSyntax, DeclaredModule>(name: "Scope Check") { mod, ctx in
        let binder = NameBinding(topLevel: mod, engine: ctx.engine,
                                 converter: ctx.currentConverter!,
                                 fileURL: ctx.options.inputURLs[0],
                                 processImportedFile: processImportedFile)
        return binder.performScopeCheck(topLevel: mod)
    })

  /// The ScopeCheck pass ensures the program is well-scoped and doesn't use
  /// unreachable variables.
  static let scopeCheckImport =
    DiagnosticGatePass(
      Pass<ModuleDeclSyntax, (DeclaredModule, LocalNames)>(
        name: "Scope Check Import") { mod, ctx in
        let binder = NameBinding(topLevel: mod, engine: ctx.engine,
                                 converter: ctx.currentConverter!,
                                 fileURL: ctx.options.inputURLs[0],
                                 processImportedFile: processImportedFile)
        let module = binder.performScopeCheck(topLevel: mod)
        return (module, binder.localNames)
    })

  /// The TypeCheck pass ensures a well-scoped program is also well-typed.
  static let typeCheck =
    DiagnosticGatePass(
      Pass<DeclaredModule, TopLevelModule>(name: "Type Check") { module, ctx in
        let tc =
          TypeChecker<CheckPhaseState>(CheckPhaseState(), ctx.engine,
              options: ctx.options.typeCheckerDebugOptions)
        return tc.checkTopLevelModule(module)
    })

  static let girGen =
    Pass<TopLevelModule, GIRModule>(name: "Generate GraphIR") { module, _ in
      let girGenModule = GIRGenModule(module)
      return girGenModule.emitTopLevelModule()
    }

  static let irGen =
    Pass<GIRModule, LLVM.Module>(name: "Generate LLVM IR") { module, _ in
      return IRGen.emit(module)
    }
}
