//
//  StandardPasses.swift
//  Drill
//
//  Created by Harlan Haskins on 11/28/17.
//

import Foundation
import Lithosphere
import Crust
import Moho

enum Passes {
  /// The Lex pass reads a URL from the file system and tokenizes it into a
  /// stream of TokenSyntax nodes.
  static let lex =
    Pass<URL, [TokenSyntax]>(name: "Lex") { url, ctx in
      do {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lexer = Lexer(input: contents, filePath: url.path)
        return lexer.tokenize()
      } catch {
        ctx.engine.diagnose(.couldNotReadInput(url))
        return nil
      }
    }

  /// The Shine pass takes a token stream and adds additional implicit tokens
  /// representing the beginning and ends of scopes.
  static let shine =
    Pass<[TokenSyntax], [TokenSyntax]>(name: "Shine") { tokens, ctx in
      layout(tokens)
    }

  /// The Parse pass runs the parser over a Shined token stream and produces a
  /// full-fledged Syntax tree.
  static let parse =
    Pass<[TokenSyntax], ModuleDeclSyntax>(name: "Parse") { tokens, ctx in
      let parser = Parser(diagnosticEngine: ctx.engine, tokens: tokens)
      return parser.parseTopLevelModule()
    }

  /// The ScopeCheck pass ensures the program is well-scoped and doesn't use
  /// unreachable variables.
  static let scopeCheck =
    DiagnosticGatePass(
      Pass<ModuleDeclSyntax, DeclaredModule>(name: "Scope Check") {
        module, ctx in
        let binder = NameBinding(topLevel: module, engine: ctx.engine)
        return binder.performScopeCheck(topLevel: module)
      })
}
