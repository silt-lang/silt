/// Scope.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere

extension NameBinding {
  public func scopeCheckModule(_ module: ModuleDeclSyntax) -> DeclaredModule {
    let params = module.typedParameterList.map(self.scopeCheckTelescope)
    let filteredDecls = self.withScope(walkNotations(module)) { _ in
      return self.reparseDecls(module.declList)
    }
    return DeclaredModule(
      moduleName: self.activeScope.nameSpace.module,
      params: params,
      namespace: self.activeScope.nameSpace,
      decls: filteredDecls.map(self.scopeCheckDecl))
  }
  
  private func scopeCheckDecl(_ syntax: DeclSyntax) -> Decl {
    precondition(!(syntax is FunctionDeclSyntax ||
      syntax is FunctionClauseDeclSyntax))
    switch syntax {
    case let syntax as ReparsedFunctionDeclSyntax:
      return self.scopeCheckFunctionDecl(syntax)
    default:
      fatalError()
    }
  }

  private func scopeCheckExpr(_ syntax: ExprSyntax) -> Expr {
    switch syntax {
    case let syntax as NamedBasicExprSyntax:
      let n = QualifiedName(ast: syntax.name)
      let head : ApplyHead
      if self.isBoundVariable(n.name) {
        head = ApplyHead.variable(n.name)
      } else {
        guard case .definition(_)? = self.lookupFullyQualifiedName(n) else {
          fatalError()
        }
        head = ApplyHead.definition(n)
      }
      return .apply(head, [])
    case _ as TypeBasicExprSyntax:
      return .type
    case _ as UnderscoreExprSyntax:
      return .meta
    case let syntax as ParenthesizedExprSyntax:
      return self.scopeCheckExpr(syntax.expr)
    case let syntax as LambdaExprSyntax:
      return self.underScope { _ in
        let bindings = self.scopeCheckBindingList(syntax.bindingList)
        let ee = self.scopeCheckExpr(syntax.bodyExpr)
        return bindings.reversed().reduce(ee) { (acc, next) in
          return .lambda(next, acc)
        }
      }
    case let syntax as ApplicationExprSyntax:
      var elims = [Elimination]()
      let n = QualifiedName(ast: (syntax.exprs[0] as! NamedBasicExprSyntax).name)

      let head : ApplyHead
      if self.isBoundVariable(n.name) {
        head = ApplyHead.variable(n.name)
      } else {
        guard case .some(.definition(_)) = self.lookupFullyQualifiedName(n) else {
          fatalError()
        }
        head = ApplyHead.definition(n)
      }

      for i in 1..<syntax.exprs.count {
        let e = syntax.exprs[i]
        let elim = Elimination.apply(self.scopeCheckExpr(e))
        elims.append(elim)
      }
      return .apply(head, elims)
    default:
      print(type(of: syntax))
      fatalError()
    }
  }

  private func scopeCheckBindingList(
    _ syntax: BindingListSyntax) -> [([Name], Expr)] {
    var bs = [([Name], Expr)]()
    for i in 0..<syntax.count {
      let binding = syntax[i]
      switch binding {
      case let binding as NamedBindingSyntax:
        let name = QualifiedName(ast: binding.name).name
        guard let bindName = self.bindVariable(named: name) else {
          fatalError()
        }
        bs.append(([bindName], .meta))
      case let binding as TypedBindingSyntax:
        bs.append(self.scopeCheckTelescope(binding.parameter))
      default:
        fatalError()
      }
    }
    return bs
  }

  private func scopeCheckTelescope(
    _ syntax: TypedParameterSyntax) -> ([Name], Expr) {
    switch syntax {
    case let syntax as ExplicitTypedParameterSyntax:
      let tyExpr = self.scopeCheckExpr(syntax.ascription.typeExpr)
      var names = [Name]()
      for j in 0..<syntax.ascription.boundNames.count {
        let name = syntax.ascription.boundNames[j]
        guard let bindName = self.bindVariable(named: Name(name: name)) else {
          fatalError()
        }
        names.append(bindName)
      }
      return (names, tyExpr)
    case let syntax as ImplicitTypedParameterSyntax:
      let tyExpr = self.scopeCheckExpr(syntax.ascription.typeExpr)
      var names = [Name]()
      for j in 0..<syntax.ascription.boundNames.count {
        let name = syntax.ascription.boundNames[j]
        guard let bindName = self.bindVariable(named: Name(name: name)) else {
          fatalError()
        }
        names.append(bindName)
      }
      return (names, tyExpr)
    default:
      fatalError()
    }
  }

  private func scopeCheckPattern(_ syntax: BasicExprListSyntax) -> [Pattern] {
    assert(!syntax.isEmpty)

    let pats = syntax.map(self.exprToDeclaredPattern)
    var patterns = [Pattern]()
    patterns.reserveCapacity(pats.count)
    for p in pats.dropFirst() {
      switch p {
      case .wild:
        patterns.append(.wild)
      case .variable(let name):
        guard let (localName, _) = self.lookupLocalName(name) else {
          guard let name = self.bindVariable(named: name) else {
            fatalError()
          }
          patterns.append(.variable(QualifiedName(name: name)))
          continue
        }
        patterns.append(.variable(localName))
      default:
        fatalError()
      }
    }
    return patterns
  }

  private func scopeCheckFunctionDecl(
    _ syntax: ReparsedFunctionDeclSyntax) -> Decl {
    precondition(syntax.ascription.boundNames.count == 1)
    let funcName = Name(name: syntax.ascription.boundNames[0])
    guard let functionName = self.bindDefinition(named: funcName, 0) else {
      fatalError()
    }
    let clauses = syntax.clauseList.map(self.scopeCheckFunctionClause)
    return Decl.function(functionName, clauses)
  }

  private func scopeCheckFunctionClause(
    _ syntax: FunctionClauseDeclSyntax) -> Clause {
    switch syntax {
    case let syntax as NormalFunctionClauseDeclSyntax:
      return self.underScope { _ in
        let pattern = self.scopeCheckPattern(syntax.basicExprList)
        let body = self.scopeCheckExpr(syntax.rhsExpr)
        return Clause(patterns: pattern, body: .body(body, []))
      }
    case let syntax as WithRuleFunctionClauseDeclSyntax:
      return self.underScope { _ in
        let pattern = self.scopeCheckPattern(syntax.basicExprList)
        let body = self.scopeCheckExpr(syntax.rhsExpr)
        // FIXME: Introduce the with variables binding too.
        return Clause(patterns: pattern, body: .body(body, []))
      }
    default:
      fatalError()
    }
  }

  private func exprToDeclaredPattern(_ e : ExprSyntax) -> DeclaredPattern {
    switch e {
    case let e as NamedBasicExprSyntax where e.name.count == 1 &&
      e.name[0].name.tokenKind == .underscore:
      return .wild
    case let e as NamedBasicExprSyntax:
      return .variable(QualifiedName(ast: e.name).name)
    case let e as ApplicationExprSyntax:
      let head = e.exprs.first! as! NamedBasicExprSyntax
      return .constructor(QualifiedName(ast: head.name),
                          e.exprs.dropFirst().map(self.exprToDeclaredPattern))
    default:
      fatalError()
    }
  }
}

extension NameBinding {
  func reparseDecls(_ ds: DeclListSyntax) -> DeclListSyntax {
    var decls = [DeclSyntax]()
//    let notes = self.newNotations(in: self.activeScope)
    var funcMap = [Name: FunctionDeclSyntax]()
    var clauseMap = [Name: [FunctionClauseDeclSyntax]]()
    for i in 0..<ds.count {
      let decl = ds[i]
      switch decl {
      case let funcDecl as FunctionDeclSyntax:
        for i in 0..<funcDecl.ascription.boundNames.count {
          let name = Name(name: funcDecl.ascription.boundNames[i])
          guard clauseMap[name] == nil else {
            self.engine.diagnose(.nameShadows(name))
            fatalError()
          }
          funcMap[name] = funcDecl
          clauseMap[name] = []
        }
      case let funcDecl as NormalFunctionClauseDeclSyntax:
        guard
          let namedExpr = funcDecl.basicExprList[0] as? NamedBasicExprSyntax
        else {
          fatalError()
        }
        let name = QualifiedName(ast: namedExpr.name).name
        guard clauseMap[name] != nil else {
          self.engine.diagnose(.bodyBeforeSignature(name))
          fatalError()
        }
        clauseMap[name]!.append(funcDecl)
      default:
        fatalError()
      }
    }

    for k in funcMap.keys {
      let function = funcMap[k]!
      let clauses = clauseMap[k]!
      let singleton = IdentifierListSyntax(elements: [ k.syntax ])
      decls.append(ReparsedFunctionDeclSyntax(
        ascription: function.ascription.withBoundNames(singleton),
        trailingSemicolon: function.trailingSemicolon,
        clauseList: FunctionClauseListSyntax(elements: clauses)))
    }

    return DeclListSyntax(elements: decls)
  }
}
