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
      return lexer.tokenize()
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
