/// ScopeCheck.swift
///
/// Copyright 2017-2018, The Silt Language Project.
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
    let moduleName = QualifiedName(ast: module.moduleIdentifier)
    let qmodName = self.qualify(name: moduleName.name)
    let params = module.typedParameterList.map(self.scopeCheckParameter)
    return self.withScope(walkNotations(module, qmodName)) { _ in
      let filteredDecls = self.reparseDecls(module.declList)
      return DeclaredModule(
        moduleName: self.activeScope.nameSpace.module,
        params: params,
        namespace: self.activeScope.nameSpace,
        decls: filteredDecls.flatMap(self.scopeCheckDecl))
    }
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
    case let syntax as FixityDeclSyntax:
      return self.scopeCheckFixityDecl(syntax)
      // FIXME: Implement import validation logic.
//    case let syntax as ImportDeclSyntax:
//    case let syntax as OpenImportDeclSyntax:
    default:
      fatalError("scope checking for \(type(of: syntax)) is unimplemented")
    }
  }

  private func formCompleteApply(_ n : FullyQualifiedName, _ args: [Expr]) -> Expr {
    let head: ApplyHead
    if self.isBoundVariable(n.name) {
      head = .variable(n.name)
    } else if let (fqn, info) = self.lookupLocalName(n.name) {
      switch info {
      case .constructor(_, _):
        return .constructor(fqn, args)
      default:
        head = .definition(fqn)
      }
    } else if self.lookupFullyQualifiedName(n) != nil {
      head = .definition(n)
    } else {
      // If it's not a definition or a local variable, it's undefined.
      // Recover by introducing a local variable binding anyways.
      self.engine.diagnose(.undeclaredIdentifier(n), node: n.node)
      head = .variable(n.name)
    }

    return .apply(head, args.map(Elimination.apply))
  }

  /// Scope check and validate an expression.
  private func scopeCheckExpr(_ syntax: ExprSyntax) -> Expr {
    switch syntax {
    case let syntax as NamedBasicExprSyntax:
      let n = QualifiedName(ast: syntax.name)
      return formCompleteApply(n, [])
    case _ as TypeBasicExprSyntax:
      return .type
    case _ as UnderscoreExprSyntax:
      return .meta
    case let syntax as ParenthesizedExprSyntax:
      return self.underScope { _ in
        return self.scopeCheckExpr(syntax.expr)
      }
    case let syntax as LambdaExprSyntax:
      return self.underScope { _ in
        let bindings = self.scopeCheckBindingList(syntax.bindingList)
        let ee = self.scopeCheckExpr(syntax.bodyExpr)
        return bindings.reversed().reduce(ee) { (acc, next) -> Expr in
          let boundNames: [Name] = next.0
          let nameTy: Expr = next.1
          return boundNames.dropFirst().reduce(nameTy) { (acc, nm) -> Expr in
            return Expr.lambda((nm, nameTy), acc)
          }
        }
      }
    case let syntax as ReparsedApplicationExprSyntax:
      guard syntax.exprs.count >= 1 else {
        return self.scopeCheckExpr(syntax.head)
      }

      let headExpr = syntax.head
      let n = QualifiedName(ast: headExpr.name)
      guard n.string != "_->_" else {
        assert(syntax.exprs.count == 2)
        if let piParams = syntax.exprs[0] as? TypedParameterGroupExprSyntax {
          return rollPi(piParams.parameters.map(self.scopeCheckParameter),
                        self.scopeCheckExpr(syntax.exprs[1])).0
        }
        return .function(self.scopeCheckExpr(syntax.exprs[0]),
                         self.scopeCheckExpr(syntax.exprs[1]))
      }

      var args = [Expr]()
      for e in syntax.exprs {
        let elim = self.scopeCheckExpr(e)
        args.append(elim)
      }

      return formCompleteApply(n, args)
    case let syntax as ApplicationExprSyntax:
      guard syntax.exprs.count > 1 else {
        return self.scopeCheckExpr(syntax.exprs[0])
      }

      switch syntax.exprs[0] {
      case let headExpr as NamedBasicExprSyntax:
        let n = QualifiedName(ast: headExpr.name)
        guard n.string != "_->_" else {
          assert(syntax.exprs.count == 3)
          if let piParams = syntax.exprs[1] as? TypedParameterGroupExprSyntax {
            return rollPi(piParams.parameters.map(self.scopeCheckParameter),
                          self.scopeCheckExpr(syntax.exprs[2])).0
          }
          return .function(self.scopeCheckExpr(syntax.exprs[1]),
                           self.scopeCheckExpr(syntax.exprs[2]))
        }

        var args = [Expr]()
        for e in syntax.exprs.dropFirst() {
          let elim = self.scopeCheckExpr(e)
          args.append(elim)
        }

        return formCompleteApply(n, args)
      default:
        fatalError("Cannot yet handle this case")
      }
    case let syntax as QuantifiedExprSyntax:
      return self.underScope { _ in
        let telescope = syntax.bindingList.map(self.scopeCheckParameter)
        return self.rollPi(telescope, self.scopeCheckExpr(syntax.outputExpr)).0
      }
    case let syntax as TypedParameterGroupExprSyntax:
      let telescope = syntax.parameters.map(self.scopeCheckParameter)
      return self.rollPi1(telescope)
    default:
      fatalError("scope checking for \(type(of: syntax)) is unimplemented")
    }
  }

  private func rollPi(
    _ telescope: [([Name], Expr)], _ cap: Expr) -> (Expr, [Name]) {
    var type = cap
    var piNames = [Name]()
    for (names, expr) in telescope.reversed() {
      for name in names.reversed() {
        type = Expr.pi(name, expr, type)
        piNames.append(name)
      }
    }
    return (type, piNames)
  }

  private func rollPi1(_ telescope: [([Name], Expr)]) -> Expr {
    precondition(!telescope.isEmpty)
    guard let first = telescope.last else {
      fatalError()
    }

    var type = first.1
    for name in first.0.dropLast().reversed() {
      type = Expr.pi(name, first.1, type)
    }

    for (names, expr) in telescope.dropLast().reversed() {
      for name in names.reversed() {
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
                      self.reparseExpr(syntax.ascription.typeExpr))
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
                      self.reparseExpr(syntax.ascription.typeExpr))
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

  private func scopeCheckPattern(
    _ syntax: BasicExprListSyntax) -> [DeclaredPattern] {
    let pats = syntax.flatMap(self.exprToDeclPattern)
    func openPatternVarsIntoScope(_ p: DeclaredPattern) -> Bool {
      switch p {
      case .wild:
        return true
      case .variable(let name):
        guard self.isBoundVariable(name) else {
          _ = self.bindVariable(named: name)
          return true
        }
        return false
      case let .constructor(_, pats):
        return pats.reduce(true, { $0 && openPatternVarsIntoScope($1) })
      }
    }
    var validPatterns = [DeclaredPattern]()
    validPatterns.reserveCapacity(pats.count)
    for pat in pats {
      guard openPatternVarsIntoScope(pat) else {
        continue
      }
      validPatterns.append(pat)
    }
    return validPatterns
  }

  private func scopeCheckDataDecl(_ syntax: DataDeclSyntax) -> [Decl] {
    let dataName = Name(name: syntax.dataIdentifier)
    guard let boundDataName = self.bindDefinition(named: dataName, 0) else {
      // If this declaration does not have a unique name, diagnose it and
      // recover by ignoring it.
      self.engine.diagnose(.nameShadows(dataName), node: syntax)
      return []
    }
    let (sig, db) = self.underScope { (_) -> (Decl, Decl) in
      let params = syntax.typedParameterList.map(self.scopeCheckParameter)
      let rebindExpr = self.reparseExpr(syntax.typeIndices.indexExpr)
      let (type, names) = self.rollPi(params, self.scopeCheckExpr(rebindExpr))
      let asc = Decl.dataSignature(TypeSignature(name: boundDataName,
                                                 type: type))
      let cs = syntax.constructorList.flatMap(self.scopeCheckConstructor)
      let dataBody = Decl.data(boundDataName, names, cs)
      return (asc, dataBody)
    }

    guard case let .data(_, _, cs) = db else {
      fatalError()
    }

    for constr in cs {
      guard self.bindConstructor(named: constr.name.name, 0, 0) != nil else {
        fatalError("Constructor names should be unique by now!")
      }
    }

    return [ sig, db ]
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
      let capType = syntax.typeIndices.map({
        return self.scopeCheckExpr(self.reparseExpr($0.indexExpr))
      }) ?? Expr.type

      let (ty, _) = rollPi(params, capType)
      let asc = Decl.recordSignature(TypeSignature(name: boundDataName,
                                                   type: ty))

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
      let maybeSig = self.underScope { (_) -> (Name, TypeSignature)? in
        let name = Name(name: synName)

        let rebindExpr = self.reparseExpr(syntax.ascription.typeExpr)
        let ascExpr = self.scopeCheckExpr(rebindExpr)

        guard let bindName = self.bindProjection(named: name, 0) else {
          // If this declaration does not have a unique name, diagnose it and
          // recover by ignoring it.
          self.engine.diagnose(.nameShadows(name), node: syntax.ascription)
          return nil
        }
        return (name, TypeSignature(name: bindName, type: ascExpr))
      }

      if let sig = maybeSig {
        result.append(sig)
      }
    }
    return result
  }

  private func scopeCheckConstructor(
    _ syntax: ConstructorDeclSyntax) -> [TypeSignature] {
    var result = [TypeSignature]()
    result.reserveCapacity(syntax.ascription.boundNames.count)
    for synName in syntax.ascription.boundNames {
      let name = Name(name: synName)

      let rebindExpr = self.reparseExpr(syntax.ascription.typeExpr)
      let ascExpr = self.scopeCheckExpr(rebindExpr)

      guard let bindName = self.bindConstructor(named: name, 0, 0) else {
        // If this declaration does not have a unique name, diagnose it and
        // recover by ignoring it.
        self.engine.diagnose(.nameShadows(name), node: syntax.ascription)
        continue
      }

      result.append(TypeSignature(name: bindName, type: ascExpr))
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
    let rebindExpr = self.reparseExpr(syntax.ascription.typeExpr)
    let ascExpr = self.underScope { _ in
      return self.scopeCheckExpr(rebindExpr)
    }
    let asc = Decl.ascription(TypeSignature(name: functionName, type: ascExpr))
    let clauses = syntax.clauseList.map(self.scopeCheckFunctionClause)
    let fn = Decl.function(functionName, clauses)
    return [asc, fn]
  }

  private func scopeCheckFunctionClause(
    _ syntax: FunctionClauseDeclSyntax) -> DeclaredClause {
    switch syntax {
    case let syntax as NormalFunctionClauseDeclSyntax:
      return self.underScope { _ in
        let pattern = self.scopeCheckPattern(syntax.basicExprList)
        let reparsedRHS = self.reparseExpr(syntax.rhsExpr)
        let body = self.scopeCheckExpr(reparsedRHS)
        return DeclaredClause(patterns: pattern, body: .body(body, []))
      }
    case let syntax as WithRuleFunctionClauseDeclSyntax:
      return self.underScope { _ in
        let pattern = self.scopeCheckPattern(syntax.basicExprList)
        let body = self.scopeCheckExpr(syntax.rhsExpr)
        // FIXME: Introduce the with variables binding too.
        return DeclaredClause(patterns: pattern, body: .body(body, []))
      }
    default:
      fatalError("Non-exhaustive match of function clause decl syntax?")
    }
  }

  private func exprToDeclPattern(_ syntax: ExprSyntax) -> [DeclaredPattern] {
    switch syntax {
    case let syntax as NamedBasicExprSyntax where syntax.name.count == 1 &&
      syntax.name[0].name.tokenKind == .underscore:
      return [.wild]
    case let syntax as NamedBasicExprSyntax:
      let headName = QualifiedName(ast: syntax.name).name
      if case let .some((fullName, .constructor(_, _))) = self.lookupLocalName(headName) {
        return [.constructor(fullName, [])]
      }
      return [.variable(headName)]
    case let syntax as ApplicationExprSyntax:
      guard
        let firstExpr = syntax.exprs.first,
        let head = firstExpr as? NamedBasicExprSyntax
      else {
        fatalError("Can't handle this kind of pattern")
      }
      let argsExpr = syntax.exprs.dropFirst().flatMap(self.exprToDeclPattern)
      let headName = QualifiedName(ast: head.name).name
      guard case let .some((fullName, .constructor(_, _))) = self.lookupLocalName(headName) else {
        fatalError()
      }
      return [.constructor(fullName, argsExpr)]
    case let syntax as ReparsedApplicationExprSyntax:
      let name = QualifiedName(ast: syntax.head.name).name
      guard case let .some(fqn, .constructor(_)) = lookupLocalName(name) else {
        return self.exprToDeclPattern(syntax.head)
             + syntax.exprs.flatMap(self.exprToDeclPattern)
      }
      return [.constructor(fqn, syntax.exprs.flatMap(self.exprToDeclPattern))]
    case let syntax as ParenthesizedExprSyntax:
      return self.exprToDeclPattern(syntax.expr)
    case _ as UnderscoreExprSyntax:
      return [.wild]
    default:
      fatalError("scope checking for \(type(of: syntax)) is unimplemented")
    }
  }
}

extension NameBinding {
  func reparseDecls(_ ds: DeclListSyntax) -> DeclListSyntax {
    var decls = [DeclSyntax]()
    var funcMap = [Name: FunctionDeclSyntax]()
    var clauseMap = [Name: [FunctionClauseDeclSyntax]]()
    var nameList = [Name]()
    for decl in ds {
      switch decl {
      case let funcDecl as FunctionDeclSyntax:
        for synName in funcDecl.ascription.boundNames {
          let name = Name(name: synName)
          guard clauseMap[name] == nil else {
            // If this declaration does not have a unique name, diagnose it and
            // recover by ignoring it.
            self.engine.diagnose(.nameShadows(name),
                                 node: funcDecl.ascription) {
              $0.note(.shadowsOriginal(name), node: funcMap[name])
            }
            continue
          }
          funcMap[name] = funcDecl
          clauseMap[name] = []
          nameList.append(name)
        }
      case let funcDecl as NormalFunctionClauseDeclSyntax:
        let (name, lhs) = self.reparseLHS(funcDecl.basicExprList)
        let reparsedDecl = funcDecl.withBasicExprList(lhs)
        guard clauseMap[name] != nil else {
          self.engine.diagnose(.bodyBeforeSignature(name), node: funcDecl)
          continue
        }
        clauseMap[name]!.append(reparsedDecl)
      default:
        decls.append(decl)
      }
    }

    for k in nameList {
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

  private func scopeCheckFixityDecl(_ syntax: FixityDeclSyntax) -> [Decl] {
    _ = fixityFromSyntax(syntax, diagnose: true)
    return []
  }
}
