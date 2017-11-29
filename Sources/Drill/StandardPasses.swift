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

  static let shine =
    Pass<[TokenSyntax], [TokenSyntax]>(name: "Shine") { tokens, ctx in
      layout(tokens)
    }

  static let parse =
    Pass<[TokenSyntax], ModuleDeclSyntax>(name: "Parse") { tokens, ctx in
      let parser = Parser(diagnosticEngine: ctx.engine, tokens: tokens)
      return parser.parseTopLevelModule()
    }

  static let scopeCheck =
    Pass<ModuleDeclSyntax, DeclaredModule>(name: "Scope Check") { module, ctx in
      let binder = NameBinding(topLevel: module, engine: ctx.engine)
      return binder.performScopeCheck(topLevel: module)
    }
}
