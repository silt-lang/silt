/// ScopeCheck.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere

extension NameBinding {
  /// Checks that a module, its parameters, and its child declarations are
  /// well-scoped.  In the process, `NameBinding` will quantify all non-local
  /// names and return a simplified well-scoped (but not yet type-correct)
  /// AST as output.
  ///
  /// Should scope check detect inconsistencies, it will diagnose terms and
  /// often drop them from its consideration - but not before binding their
  /// names into scope to aid recovery.
  ///
  /// This pass does not fail thus it is crucial that the diagnostic
  /// engine be checked before continuing on to the semantic passes.
  public func scopeCheckModule(_ module: ModuleDeclSyntax) -> DeclaredModule {
    let params = module.typedParameterList.map(self.scopeCheckParameter)
    let filteredDecls = self.withScope(walkNotations(module)) { _ in
      return self.reparseDecls(module.declList)
    }
    return DeclaredModule(
      moduleName: self.activeScope.nameSpace.module,
      params: params,
      namespace: self.activeScope.nameSpace,
      decls: filteredDecls.flatMap(self.scopeCheckDecl))
  }

  /// Scope check a declaration that may be found directly under a module.
  private func scopeCheckDecl(_ syntax: DeclSyntax) -> [Decl] {
    precondition(!(syntax is FunctionDeclSyntax ||
      syntax is FunctionClauseDeclSyntax))
    switch syntax {
    case let syntax as ModuleDeclSyntax:
      return [.module(self.scopeCheckModule(syntax))]
    case let syntax as ReparsedFunctionDeclSyntax:
      return self.scopeCheckFunctionDecl(syntax)
    case let syntax as DataDeclSyntax:
      return self.scopeCheckDataDecl(syntax)
    case let syntax as RecordDeclSyntax:
      return self.scopeCheckRecordDecl(syntax)
      // FIXME: Implement import validation logic.
//    case let syntax as ImportDeclSyntax:
//    case let syntax as OpenImportDeclSyntax:
    default:
      fatalError("scope checking for \(type(of: syntax)) is unimplemented")
    }
  }

  /// Scope check and validate an expression.
  private func scopeCheckExpr(_ syntax: ExprSyntax) -> Expr {
    switch syntax {
    case let syntax as NamedBasicExprSyntax:
      let n = QualifiedName(ast: syntax.name)
      let head: ApplyHead
      if self.isBoundVariable(n.name) {
        head = .variable(n.name)
      } else if let nameInfo = self.lookupFullyQualifiedName(n) {
        guard case .definition(_) = nameInfo else {
          return .constructor(n, [])
        }
        head = .definition(n)
      } else if let (fqn, nameInfo) = self.lookupLocalName(n.name) {
        guard case .definition(_) = nameInfo else {
          return .constructor(fqn, [])
        }
        head = .definition(fqn)
      } else {
        // If it's not a definition or a local variable, it's undefined.
        // Recover by introducing a local variable binding anyways.
        self.engine.diagnose(.undeclaredIdentifier(n), node: n.node)
        head = .variable(n.name)
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
      for e in syntax.exprs.dropFirst() {
        let elim = self.scopeCheckExpr(e)
        args.append(elim)
      }

      let head: ApplyHead
      if self.isBoundVariable(n.name) {
        head = .variable(n.name)
      } else if let (fqn, _) = self.lookupLocalName(n.name) {
        head = .definition(fqn)
      } else if self.lookupFullyQualifiedName(n) != nil {
        head = .definition(n)
      } else {
        // If it's not a definition or a local variable, it's undefined.
        // Recover by introducing a local variable binding anyways.
        self.engine.diagnose(.undeclaredIdentifier(n), node: n.node)
        head = .variable(n.name)
      }

      return .apply(head, args.map(Elimination.apply))
    case let syntax as QuantifiedExprSyntax:
      return self.underScope { _ in
        let telescope = syntax.bindingList.map(self.scopeCheckParameter)
        return self.rollPi(telescope, self.scopeCheckExpr(syntax.outputExpr))
      }
    case let syntax as TypedParameterGroupExprSyntax:
      let telescope = syntax.parameters.map(self.scopeCheckParameter)
      return self.rollPi1(telescope)
    default:
      fatalError("scope checking for \(type(of: syntax)) is unimplemented")
    }
  }

  private func rollPi(_ telescope: [([Name], Expr)], _ cap : Expr) -> Expr {
    var type = cap
    for (names, expr) in telescope {
      for name in names {
        type = Expr.pi(name, expr, type)
      }
    }
    return type
  }

  private func rollPi1(_ telescope: [([Name], Expr)]) -> Expr {
    precondition(!telescope.isEmpty)
    guard let first = telescope.first else {
      fatalError()
    }

    var type = first.1
    for name in first.0.dropFirst() {
      type = Expr.pi(name, first.1, type)
    }

    for (names, expr) in telescope {
      for name in names {
        type = Expr.pi(name, expr, type)
      }
    }
    return type
  }

  private func scopeCheckBindingList(
    _ syntax: BindingListSyntax) -> [([Name], Expr)] {
    var bs = [([Name], Expr)]()
    for binding in syntax {
      switch binding {
      case let binding as NamedBindingSyntax:
        let name = QualifiedName(ast: binding.name).name
        guard let bindName = self.bindVariable(named: name) else {
          // If this declaration is trying to bind with a reserved name,
          // ignore it.
          continue
        }
        bs.append(([bindName], .meta))
      case let binding as TypedBindingSyntax:
        bs.append(self.scopeCheckParameter(binding.parameter))
      default:
        fatalError()
      }
    }
    return bs
  }

  private func scopeCheckParameter(
    _ syntax: TypedParameterSyntax) -> ([Name], Expr) {
    switch syntax {
    case let syntax as ExplicitTypedParameterSyntax:
      let tyExpr = self.scopeCheckExpr(
                      self.rebindArrows(syntax.ascription.typeExpr))
      var names = [Name]()
      for synName in syntax.ascription.boundNames {
        let name = Name(name: synName)
        guard !self.isBoundVariable(name) else {
          // If this declaration does not have a unique name, diagnose it and
          // recover by ignoring it.
          self.engine.diagnose(.nameShadows(name), node: syntax.ascription)
          continue
        }

        guard let bindName = self.bindVariable(named: name) else {
          // If this declaration is trying to bind with a reserved name,
          // ignore it.
          continue
        }
        names.append(bindName)
      }
      return (names, tyExpr)
    case let syntax as ImplicitTypedParameterSyntax:
      let tyExpr = self.scopeCheckExpr(
                      self.rebindArrows(syntax.ascription.typeExpr))
      var names = [Name]()
      for synName in syntax.ascription.boundNames {
        let name = Name(name: synName)
        guard !self.isBoundVariable(name) else {
          // If this declaration does not have a unique name, diagnose it and
          // recover by ignoring it.
          self.engine.diagnose(.nameShadows(name), node: syntax.ascription)
          continue
        }

        guard let bindName = self.bindVariable(named: name) else {
          // If this declaration is trying to bind with a reserved name,
          // ignore it.
          continue
        }
        names.append(bindName)
      }
      return (names, tyExpr)
    default:
      fatalError("scope checking for \(type(of: syntax)) is unimplemented")
    }
  }

  private func scopeCheckDeclaredPattern(
    _ syntax: DeclaredPattern) -> Pattern? {
    switch syntax {
    case .wild:
      return .wild
    case let .variable(name):
      guard let (localName, _) = self.lookupLocalName(name) else {
        guard let name = self.bindVariable(named: name) else {
          // If this declaration is trying to bind with a reserved name,
          // ignore it.
          return nil
        }
        return .variable(QualifiedName(name: name))
      }
      return .variable(localName)
    case let .constructor(name, patterns):
      return .constructor(name,
                          patterns.flatMap(self.scopeCheckDeclaredPattern))
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
            // If this declaration is trying to bind with a reserved name,
            // ignore it.
            continue
          }
          patterns.append(.variable(QualifiedName(name: name)))
          continue
        }
        patterns.append(.variable(localName))
      case let .constructor(n, ps):
        let pats = ps.flatMap(self.scopeCheckDeclaredPattern)
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
      for (exprIdx, expr) in syntax.exprs.enumerated() {
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
    case let syntax as TypedParameterGroupExprSyntax:
      return syntax
    default:
      fatalError("arrow rebinding for \(type(of: syntax)) is unimplemented")
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
      let params = syntax.typedParameterList.map(self.scopeCheckParameter)
      // FIXME: This is not a substitute for real mixfix operators
      let rebindExpr = self.rebindArrows(syntax.typeIndices.indexExpr)
      let type = self.rollPi(params, self.scopeCheckExpr(rebindExpr))
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

  private func scopeCheckRecordDecl(_ syntax: RecordDeclSyntax) -> [Decl] {
    let recName = Name(name: syntax.recordName)
    guard let boundDataName = self.bindDefinition(named: recName, 0) else {
      // If this declaration does not have a unique name, diagnose it and
      // recover by ignoring it.
      self.engine.diagnose(.nameShadows(recName), node: syntax)
      return []
    }
    return self.underScope { _ in
      let params = syntax.parameterList.map(self.scopeCheckParameter)
      // FIXME: This is not a substitute for real mixfix operators
      var type = syntax.typeIndices.map({
        return self.scopeCheckExpr(self.rebindArrows($0.indexExpr))
      }) ?? Expr.type
      for (names, expr) in params {
        for name in names {
          type = Expr.pi(name, expr, type)
        }
      }
      let asc = Decl.recordSignature(TypeSignature(name: boundDataName,
                                                   type: type))

      var sigs = [(Name, TypeSignature)]()
      var decls = [Decl]()
      var constr: QualifiedName? = nil
      for re in syntax.recordElementList {
        if let field = re as? FieldDeclSyntax {
          sigs.append(contentsOf: self.scopeCheckFieldDecl(field))
          continue
        }

        if let funcField = re as? FunctionDeclSyntax {
          decls.append(contentsOf: self.scopeCheckDecl(funcField))
          continue
        }

        if let recConstr = re as? RecordConstructorDeclSyntax {
          let name = Name(name: recConstr.constructorName)
          guard let bindName = self.bindConstructor(named: name, 0, 0) else {
            // If this declaration does not have a unique name, diagnose it and
            // recover by ignoring it.
            self.engine.diagnose(.nameShadows(name), node: recConstr)
            continue
          }
          constr = bindName
          continue
        }
      }
      guard let recConstr = constr else {
        self.engine.diagnose(.recordMissingConstructor(boundDataName),
                             node: syntax)
        return []
      }
      let recordDecl: Decl = .record(boundDataName, sigs.map {$0.0},
                                     recConstr, sigs.map {$0.1})
      return [asc, recordDecl] + decls
    }
  }

  private func scopeCheckFieldDecl(
    _ syntax: FieldDeclSyntax) -> [(Name, TypeSignature)] {
    var result = [(Name, TypeSignature)]()
    result.reserveCapacity(syntax.ascription.boundNames.count)
    for synName in syntax.ascription.boundNames {
      let name = Name(name: synName)

      // FIXME: This is not a substitute for real mixfix operators
      let rebindExpr = self.rebindArrows(syntax.ascription.typeExpr)
      let ascExpr = self.scopeCheckExpr(rebindExpr)

      guard let bindName = self.bindProjection(named: name, 0) else {
        // If this declaration does not have a unique name, diagnose it and
        // recover by ignoring it.
        self.engine.diagnose(.nameShadows(name), node: syntax.ascription)
        continue
      }

      result.append((name, TypeSignature(name: bindName, type: ascExpr)))
    }
    return result
  }

  private func scopeCheckConstructor(
    _ syntax: ConstructorDeclSyntax) -> [(Name, TypeSignature)] {
    var result = [(Name, TypeSignature)]()
    result.reserveCapacity(syntax.ascription.boundNames.count)
    for synName in syntax.ascription.boundNames {
      let name = Name(name: synName)

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
    let ascExpr = self.underScope { _ in
      return self.scopeCheckExpr(rebindExpr)
    }
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
      fatalError("Non-exhaustive match of function clause decl syntax?")
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
      fatalError("scope checking for \(type(of: syntax)) is unimplemented")
    }
  }
}

extension NameBinding {
  func reparseDecls(_ ds: DeclListSyntax) -> DeclListSyntax {
    var decls = [DeclSyntax]()
//    let notes = self.newNotations(in: self.activeScope)
    var funcMap = [Name: FunctionDeclSyntax]()
    var clauseMap = [Name: [FunctionClauseDeclSyntax]]()
    for decl in ds {
      switch decl {
      case let funcDecl as FunctionDeclSyntax:
        for synName in funcDecl.ascription.boundNames {
          let name = Name(name: synName)
          guard clauseMap[name] == nil else {
            // If this declaration does not have a unique name, diagnose it and
            // recover by ignoring it.
            self.engine.diagnose(.nameShadows(name), node: funcDecl.ascription) {
              $0.note(.shadowsOriginal(name), node: funcMap[name])
            }
            continue
          }
          funcMap[name] = funcDecl
          clauseMap[name] = []
        }
      case let funcDecl as NormalFunctionClauseDeclSyntax:
        guard
          let namedExpr = funcDecl.basicExprList[0] as? NamedBasicExprSyntax
        else {
          fatalError("Can't handle this kind of function clause yet")
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
