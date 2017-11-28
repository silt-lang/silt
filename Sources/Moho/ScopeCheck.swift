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
      decls: filteredDecls.flatMap(self.scopeCheckDecl))
  }

  private func scopeCheckDecl(_ syntax: DeclSyntax) -> [Decl] {
    precondition(!(syntax is FunctionDeclSyntax ||
      syntax is FunctionClauseDeclSyntax))
    switch syntax {
    case let syntax as ReparsedFunctionDeclSyntax:
      return self.scopeCheckFunctionDecl(syntax)
    case let syntax as DataDeclSyntax:
      return self.scopeCheckDataDecl(syntax)
    default:
      print(type(of: syntax))
      fatalError()
    }
  }

  private func scopeCheckExpr(_ syntax: ExprSyntax) -> Expr {
    switch syntax {
    case let syntax as NamedBasicExprSyntax:
      let n = QualifiedName(ast: syntax.name)
      let head: ApplyHead
      if self.isBoundVariable(n.name) {
        head = ApplyHead.variable(n.name)
      } else if let nameInfo = self.lookupFullyQualifiedName(n) {
        guard case .definition(_) = nameInfo else {
          return .constructor(n, [])
        }
        head = ApplyHead.definition(n)
      } else if let (fqn, nameInfo) = self.lookupLocalName(n.name) {
        guard case .definition(_) = nameInfo else {
          return .constructor(fqn, [])
        }
        head = ApplyHead.definition(fqn)
      } else {
        // If it's not a definition or a local variable, it's undefined.
        // Recover by introducing a local variable binding anyways.
        self.engine.diagnose(.undeclaredIdentifier(n), node: n.node)
        head = ApplyHead.variable(n.name)
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
      guard syntax.exprs.count > 1 else {
        return self.scopeCheckExpr(syntax.exprs[0])
      }

      guard let headExpr = syntax.exprs[0] as? NamedBasicExprSyntax else {
        fatalError("Cannot yet handle this case")
      }

      let n = QualifiedName(ast: headExpr.name)
      guard n.string != "->" else {
        assert(syntax.exprs.count == 3)
        return .function(self.scopeCheckExpr(syntax.exprs[1]),
                         self.scopeCheckExpr(syntax.exprs[2]))
      }

      var args = [Expr]()
      for i in 1..<syntax.exprs.count {
        let e = syntax.exprs[i]
        let elim = self.scopeCheckExpr(e)
        args.append(elim)
      }

      let head: ApplyHead
      if self.isBoundVariable(n.name) {
        head = ApplyHead.variable(n.name)
      } else if let (fqn, _) = self.lookupLocalName(n.name) {
        head = ApplyHead.definition(fqn)
      } else if self.lookupFullyQualifiedName(n) != nil {
        head = ApplyHead.definition(n)
      } else {
        // If it's not a definition or a local variable, it's undefined.
        // Recover by introducing a local variable binding anyways.
        self.engine.diagnose(.undeclaredIdentifier(n), node: n.node)
        head = ApplyHead.variable(n.name)
      }

      return .apply(head, args.map(Elimination.apply))
    case let syntax as QuantifiedExprSyntax:
      return self.underScope { _ in
        let telescope = syntax.bindingList.map(self.scopeCheckTelescope)
        var type = self.scopeCheckExpr(syntax.outputExpr)
        for (names, expr) in telescope {
          for name in names {
            type = Expr.pi(name, expr, type)
          }
        }
        return type
      }
    case let syntax as TypedParameterArrowExprSyntax:
      let telescope = syntax.parameters.map(self.scopeCheckTelescope)
      var type = self.scopeCheckExpr(syntax.outputExpr)
      for (names, expr) in telescope {
        for name in names {
          type = Expr.pi(name, expr, type)
        }
      }
      return type
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
      let tyExpr = self.scopeCheckExpr(
                      self.rebindArrows(syntax.ascription.typeExpr))
      var names = [Name]()
      for j in 0..<syntax.ascription.boundNames.count {
        let name = Name(name: syntax.ascription.boundNames[j])
        guard !self.isBoundVariable(name) else {
          // If this declaration does not have a unique name, diagnose it and
          // recover by ignoring it.
          self.engine.diagnose(.nameShadows(name), node: syntax.ascription)
          continue
        }

        guard let bindName = self.bindVariable(named: name) else {
          fatalError()
        }
        names.append(bindName)
      }
      return (names, tyExpr)
    case let syntax as ImplicitTypedParameterSyntax:
      let tyExpr = self.scopeCheckExpr(
                      self.rebindArrows(syntax.ascription.typeExpr))
      var names = [Name]()
      for j in 0..<syntax.ascription.boundNames.count {
        let name = Name(name: syntax.ascription.boundNames[j])
        guard !self.isBoundVariable(name) else {
          // If this declaration does not have a unique name, diagnose it and
          // recover by ignoring it.
          self.engine.diagnose(.nameShadows(name), node: syntax.ascription)
          continue
        }

        guard let bindName = self.bindVariable(named: name) else {
          fatalError("Name should be unique by now!")
        }
        names.append(bindName)
      }
      return (names, tyExpr)
    default:
      fatalError()
    }
  }

  private func scopeCheckDeclaredPattern(_ syntax: DeclaredPattern) -> Pattern {
    switch syntax {
    case .wild:
      return .wild
    case let .variable(name):
      guard let (localName, _) = self.lookupLocalName(name) else {
        guard let name = self.bindVariable(named: name) else {
          fatalError("Lookup failed, Name should be unbound!")
        }
        return .variable(QualifiedName(name: name))
      }
      return .variable(localName)
    case let .constructor(name, ps):
      return .constructor(name, ps.map(self.scopeCheckDeclaredPattern))
    }
  }

  private func scopeCheckPattern(_ syntax: BasicExprListSyntax) -> [Pattern] {
    assert(!syntax.isEmpty)

    let pats = syntax.map(self.exprToDeclPattern)
    var patterns = [Pattern]()
    patterns.reserveCapacity(pats.count)
    for p in pats.dropFirst() {
      switch p {
      case .wild:
        patterns.append(.wild)
      case .variable(let name):
        guard let (localName, _) = self.lookupLocalName(name) else {
          guard let name = self.bindVariable(named: name) else {
            fatalError("Lookup failed, Name should be unbound!")
          }
          patterns.append(.variable(QualifiedName(name: name)))
          continue
        }
        patterns.append(.variable(localName))
      case let .constructor(n, ps):
        let pats = ps.map(self.scopeCheckDeclaredPattern)
        patterns.append(.constructor(n, pats))
      }
    }
    return patterns
  }

  // FIXME: Remove this and really implement mixfix operators, dummy.
  private func rebindArrows(_ syntax: ExprSyntax) -> ExprSyntax {
    switch syntax {
    case let syntax as ParenthesizedExprSyntax:
      return syntax.withExpr(self.rebindArrows(syntax.expr))
    case let syntax as ApplicationExprSyntax:
      guard syntax.exprs.count > 1 else {
        return syntax.exprs[0]
      }

      var precExprs = [BasicExprSyntax]()
      for exprIdx in 0..<syntax.exprs.count {
        let expr = syntax.exprs[exprIdx]
        if
          let tokExpr = expr as? NamedBasicExprSyntax,
          QualifiedName(ast: tokExpr.name).string == "->"
        {
          let prevApp = ApplicationExprSyntax(exprs:
            BasicExprListSyntax(elements: precExprs))
          let prevExpr = ParenthesizedExprSyntax(
            leftParenToken: TokenSyntax(.leftParen),
            expr: self.rebindArrows(prevApp),
            rightParenToken: TokenSyntax(.rightParen)
          )

          let nextApp = ApplicationExprSyntax(exprs:
            BasicExprListSyntax(elements:
              Array(syntax.exprs[exprIdx+1..<syntax.exprs.endIndex])))
          let nextExpr = ParenthesizedExprSyntax(
            leftParenToken: TokenSyntax(.leftParen),
            expr: self.rebindArrows(nextApp),
            rightParenToken: TokenSyntax(.rightParen)
          )
          return ParenthesizedExprSyntax(
            leftParenToken: TokenSyntax(.leftParen),
            expr: ApplicationExprSyntax(exprs:
              BasicExprListSyntax(elements: [ tokExpr, prevExpr, nextExpr ])),
            rightParenToken: TokenSyntax(.rightParen)
          )
        } else {
          precExprs.append(expr)
        }
      }
      return syntax
    case let syntax as QuantifiedExprSyntax:
      return syntax.withOutputExpr(self.rebindArrows(syntax.outputExpr))
    case let syntax as TypedParameterArrowExprSyntax:
      return syntax.withOutputExpr(self.rebindArrows(syntax.outputExpr))
    default:
      print(type(of: syntax))
      fatalError()
    }
  }

  private func scopeCheckDataDecl(_ syntax: DataDeclSyntax) -> [Decl] {
    let dataName = Name(name: syntax.dataIdentifier)
    guard let boundDataName = self.bindDefinition(named: dataName, 0) else {
      // If this declaration does not have a unique name, diagnose it and
      // recover by ignoring it.
      self.engine.diagnose(.nameShadows(dataName), node: syntax)
      return []
    }
    let (sig, cs) = self.underScope { (_) -> (Decl, [(Name, TypeSignature)]) in
      let params = syntax.typedParameterList.map(self.scopeCheckTelescope)
      // FIXME: This is not a substitute for real mixfix operators
      let rebindExpr = self.rebindArrows(syntax.typeIndices.indexExpr)
      var type = self.scopeCheckExpr(rebindExpr)
      for (names, expr) in params {
        for name in names {
          type = Expr.pi(name, expr, type)
        }
      }
      let asc = Decl.dataSignature(TypeSignature(name: boundDataName,
                                                 type: type))
      let cs = syntax.constructorList.flatMap(self.scopeCheckConstructor)
      return (asc, cs)
    }

    for (name, _) in cs {
      guard self.bindConstructor(named: name, 0, 0) != nil else {
        fatalError("Constructor names should be unique by now!")
      }
    }

    return [ sig, .data(boundDataName, cs.map {$0.0}, cs.map {$0.1}) ]
  }

  private func scopeCheckConstructor(
    _ syntax: ConstructorDeclSyntax) -> [(Name, TypeSignature)] {
    var result = [(Name, TypeSignature)]()
    result.reserveCapacity(syntax.ascription.boundNames.count)
    for j in 0..<syntax.ascription.boundNames.count {
      let name = Name(name: syntax.ascription.boundNames[j])

      // FIXME: This is not a substitute for real mixfix operators
      let rebindExpr = self.rebindArrows(syntax.ascription.typeExpr)
      let ascExpr = self.scopeCheckExpr(rebindExpr)

      guard let bindName = self.bindConstructor(named: name, 0, 0) else {
        // If this declaration does not have a unique name, diagnose it and
        // recover by ignoring it.
        self.engine.diagnose(.nameShadows(name), node: syntax.ascription)
        continue
      }

      result.append((name, TypeSignature(name: bindName, type: ascExpr)))
    }
    return result
  }

  private func scopeCheckFunctionDecl(
    _ syntax: ReparsedFunctionDeclSyntax) -> [Decl] {
    precondition(syntax.ascription.boundNames.count == 1)

    let funcName = Name(name: syntax.ascription.boundNames[0])
    guard let functionName = self.bindDefinition(named: funcName, 0) else {
      fatalError("Should have unique function names by now")
    }
    // FIXME: This is not a substitute for real mixfix operators
    let rebindExpr = self.rebindArrows(syntax.ascription.typeExpr)
    let ascExpr = self.scopeCheckExpr(rebindExpr)
    let asc = Decl.ascription(TypeSignature(name: functionName, type: ascExpr))
    let clauses = syntax.clauseList.map(self.scopeCheckFunctionClause)
    let fn = Decl.function(functionName, clauses)
    return [asc, fn]
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

  private func exprToDeclPattern(_ syntax: ExprSyntax) -> DeclaredPattern {
    switch syntax {
    case let syntax as NamedBasicExprSyntax where syntax.name.count == 1 &&
      syntax.name[0].name.tokenKind == .underscore:
      return .wild
    case let syntax as NamedBasicExprSyntax:
      return .variable(QualifiedName(ast: syntax.name).name)
    case let syntax as ApplicationExprSyntax:
      guard
        let firstExpr = syntax.exprs.first,
        let head = firstExpr as? NamedBasicExprSyntax
      else {
        fatalError("Can't handle this kind of pattern")
      }
      return .constructor(QualifiedName(ast: head.name),
                          syntax.exprs.dropFirst().map(self.exprToDeclPattern))
    case let syntax as ParenthesizedExprSyntax:
      return self.exprToDeclPattern(syntax.expr)
    default:
      print(type(of: syntax))
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
            // If this declaration does not have a unique name, diagnose it and
            // recover by ignoring it.
            self.engine.diagnose(.nameShadows(name), node: funcDecl.ascription)
            continue
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
          self.engine.diagnose(.bodyBeforeSignature(name), node: funcDecl)
          continue
        }
        clauseMap[name]!.append(funcDecl)
      default:
        decls.append(decl)
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
