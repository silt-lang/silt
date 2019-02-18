/// ScopeCheck.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Foundation

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
  public func scopeCheckModule(_ module: ModuleDeclSyntax,
                               topLevel: Bool = false) -> DeclaredModule {
    let moduleName = QualifiedName(ast: module.moduleIdentifier)
    let params = module.typedParameterList.map(self.scopeCheckParameter)
    let qmodName: QualifiedName
    if topLevel {
      qmodName = moduleName
    } else {
      qmodName = self.activeScope.qualify(name: moduleName.name)
    }
    let noteScope = walkNotations(module, qmodName)

    let moduleCheck: (Scope) -> DeclaredModule = { _ in
      let filteredDecls = self.reparseDecls(module.declList)
      return DeclaredModule(
        moduleName: self.activeScope.nameSpace.module,
        params: params,
        namespace: self.activeScope.nameSpace,
        decls: filteredDecls.flatMap(self.scopeCheckDecl))
    }

    if topLevel {
      self.activeScope = noteScope
      return moduleCheck(noteScope)
    } else {
      return self.withScope(walkNotations(module, qmodName), moduleCheck)
    }
  }

  /// Scope check a declaration that may be found directly under a module.
  private func scopeCheckDecl(_ syntax: DeclSyntax) -> [Decl] {
    precondition(!(syntax is FunctionDeclSyntax ||
      syntax is FunctionClauseDeclSyntax))
    switch syntax {
    case let syntax as LetBindingDeclSyntax:
      return self.scopeCheckLetBinding(syntax)
    case let syntax as ModuleDeclSyntax:
      return [.module(self.scopeCheckModule(syntax))]
    case let syntax as ReparsedFunctionDeclSyntax:
      return self.scopeCheckFunctionDecl(syntax)
    case let syntax as DataDeclSyntax:
      return self.scopeCheckDataDecl(syntax)
    case let syntax as EmptyDataDeclSyntax:
      return self.scopeCheckEmptyDataDecl(syntax)
    case let syntax as RecordDeclSyntax:
      return self.scopeCheckRecordDecl(syntax)
    case let syntax as FixityDeclSyntax:
      return self.scopeCheckFixityDecl(syntax)
    case let syntax as ImportDeclSyntax:
      return self.scopeCheckImportDecl(syntax)
    case let syntax as OpenImportDeclSyntax:
      return self.scopeCheckOpenImportDecl(syntax)
    default:
      fatalError("scope checking for \(type(of: syntax)) is unimplemented")
    }
  }

  private func formCompleteApply(
    _ n: FullyQualifiedName, _ argBuf: [Expr]) -> Expr {
    let head: ApplyHead
    var args = [Expr]()
    args.reserveCapacity(argBuf.count)
    guard let resolution = self.resolveQualifiedName(n) else {
      // If it's not a definition or a local variable, it's undefined.
      // Recover by introducing a local variable binding anyways.
      self.engine.diagnose(.undeclaredIdentifier(n), node: n.node)
      head = .variable(n.name)
      args.append(contentsOf: argBuf)
      return .apply(head, args.map(Elimination.apply))
    }

    switch resolution {
    case let .variable(h):
      head = .variable(h)
      args.append(contentsOf: argBuf)
    case let .nameInfo(fqn, info):
      switch info {
      case let .definition(plicity):
        head = .definition(fqn)
        let (result, _) = self.consumeArguments(argBuf, plicity,
                                                Expr.meta, { [$0] },
                                                allowExtraneous: true)
        args.append(contentsOf: result)
      case let .constructor(set):
        args.append(contentsOf: argBuf)
        return .constructor(n, set.map { $0.0 }, args)
      default:
        head = .definition(fqn)
        args.append(contentsOf: argBuf)
      }
    }

    return .apply(head, args.map(Elimination.apply))
  }

  /// Scope check and validate an expression.
  private func scopeCheckExpr(_ syntax: ExprSyntax) -> Expr {
    switch syntax {
    case let syntax as NamedBasicExprSyntax:
      let n = QualifiedName(ast: syntax.name)
      return self.formCompleteApply(n, [])
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
          let boundNames: [Name] = next.names
          let paramAsc: Expr = next.ascription
          return boundNames.reduce(acc) { (acc, nm) -> Expr in
            return Expr.lambda((nm, paramAsc), acc)
          }
        }
      }
    case let syntax as ReparsedApplicationExprSyntax:
      guard syntax.exprs.count >= 1 else {
        return self.scopeCheckExpr(syntax.head)
      }

      let headExpr = syntax.head
      let n = QualifiedName(ast: headExpr.name)
      guard n.string != NewNotation.arrowNotation.name.string else {
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

      return self.formCompleteApply(n, args)
    case let syntax as ApplicationExprSyntax:
      guard syntax.exprs.count > 1 else {
        return self.scopeCheckExpr(syntax.exprs[0])
      }

      switch syntax.exprs[0] {
      case let headExpr as NamedBasicExprSyntax:
        let n = QualifiedName(ast: headExpr.name)
        guard n.string != NewNotation.arrowNotation.name.string else {
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

        return self.formCompleteApply(n, args)
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
    case let syntax as LetExprSyntax:
      return self.underScope { _ in
        let reparsedDecls = self.reparseDecls(syntax.declList,
                                              allowOmittingSignatures: true)
        let decls = reparsedDecls.flatMap(self.scopeCheckDecl)
        let output = self.scopeCheckExpr(syntax.outputExpr)
        return Expr.let(decls, output)
      }
    default:
      fatalError("scope checking for \(type(of: syntax)) is unimplemented")
    }
  }

  // swiftlint:disable large_tuple
  private func rollPi(
    _ telescope: [DeclaredParameter], _ cap: Expr
  ) -> (Expr, [Name], [ArgumentPlicity]) {
    var type = cap
    var piNames = [Name]()
    var plicities = [ArgumentPlicity]()
    for param in telescope.reversed() {
      for name in param.names.reversed() {
        type = Expr.pi(name, param.ascription, type)
        piNames.append(name)
        plicities.append(param.plicity)
      }
    }
    return (type, piNames.reversed(), plicities.reversed())
  }

  private func rollPi1(_ telescope: [DeclaredParameter]) -> Expr {
    precondition(!telescope.isEmpty)
    guard let first = telescope.last else {
      fatalError()
    }

    var type = first.ascription
    for name in first.names.dropLast().reversed() {
      type = Expr.pi(name, first.ascription, type)
    }

    for param in telescope.dropLast().reversed() {
      for name in param.names.reversed() {
        type = Expr.pi(name, param.ascription, type)
      }
    }
    return type
  }

  private func scopeCheckBindingList(
    _ syntax: BindingListSyntax) -> [DeclaredParameter] {
    var bs = [DeclaredParameter]()
    for binding in syntax {
      switch binding {
      case let binding as NamedBindingSyntax:
        let name = QualifiedName(ast: binding.name).name
        guard let bindName = self.bindVariable(named: name) else {
          // If this declaration is trying to bind with a reserved name,
          // ignore it.
          continue
        }
        bs.append(DeclaredParameter([bindName], .meta, .explicit))
      case let binding as TypedBindingSyntax:
        bs.append(self.scopeCheckParameter(binding.parameter))
      case _ as AnonymousBindingSyntax:
        bs.append(DeclaredParameter([Name(name: SyntaxFactory.makeUnderscore())],
                                    .meta, .explicit))
      default:
        fatalError()
      }
    }
    return bs
  }

  private func scopeCheckLetBinding(_ syntax: LetBindingDeclSyntax) -> [Decl] {
    typealias ScopeCheckType =
      (QualifiedName, Expr, [ArgumentPlicity], [DeclaredPattern])
    let (qualName, body, plicity, patterns) =
      self.underScope { _ -> ScopeCheckType in
      let plicity = Array(repeating: ArgumentPlicity.explicit,
                          count: syntax.basicExprList.count)
      let patterns = self.scopeCheckPattern(syntax.basicExprList, plicity)
      let reparsedRHS = self.reparseExpr(syntax.boundExpr)
      let body = self.scopeCheckExpr(reparsedRHS)
      let qualName = QualifiedName(ast: syntax.head.name)
      return (qualName, body, plicity, patterns)
    }

    guard let name = self.bindDefinition(named: qualName.name, plicity) else {
      engine.diagnose(.nameShadows(qualName.name), node: syntax.head) {
        $0.highlight(syntax.head)
      }
      return []
    }
    let clause = DeclaredClause(patterns: patterns, body: .body(body, []))
    return [Decl.letBinding(name, clause)]
  }

  private func scopeCheckParameter(
    _ syntax: TypedParameterSyntax) -> DeclaredParameter {
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
          self.engine.diagnose(.nameShadows(name), node: syntax.ascription) {
            $0.highlight(syntax.ascription)
          }
          continue
        }

        guard let bindName = self.bindVariable(named: name) else {
          // If this declaration is trying to bind with a reserved name,
          // ignore it.
          continue
        }
        names.append(bindName)
      }
      return DeclaredParameter(names, tyExpr, .explicit)
    case let syntax as ImplicitTypedParameterSyntax:
      let tyExpr = self.scopeCheckExpr(
                      self.reparseExpr(syntax.ascription.typeExpr))
      var names = [Name]()
      for synName in syntax.ascription.boundNames {
        let name = Name(name: synName)
        guard !self.isBoundVariable(name) else {
          // If this declaration does not have a unique name, diagnose it and
          // recover by ignoring it.
          self.engine.diagnose(.nameShadows(name), node: syntax.ascription) {
            $0.highlight(syntax.ascription)
          }
          continue
        }

        guard let bindName = self.bindVariable(named: name) else {
          // If this declaration is trying to bind with a reserved name,
          // ignore it.
          continue
        }
        names.append(bindName)
      }
      return DeclaredParameter(names, tyExpr, .implicit)
    default:
      fatalError("scope checking for \(type(of: syntax)) is unimplemented")
    }
  }

  private func scopeCheckWhereClause(
    _ syntax: FunctionWhereClauseDeclSyntax?) -> [Decl] {
    guard let syntax = syntax else {
      return []
    }
    let reparsedDecls = self.reparseDecls(syntax.declList)
    return reparsedDecls.flatMap(self.scopeCheckDecl)
  }

  private func scopeCheckPattern(
    _ syntax: BasicExprListSyntax, _ plicity: [ArgumentPlicity],
    expectAbsurd: Bool = false
  ) -> [DeclaredPattern] {
    let (pats, maybeError) = self.consumeArguments(syntax, plicity,
                                                   DeclaredPattern.wild,
                                                   self.exprToDeclPattern)
    if let err = maybeError {
      switch err {
      case let .extraneousArguments(expected, have, implicit, leftoverStart):
        let diag: Diagnostic.Message =
          .tooManyPatternsInLHS(expected, have, implicit)
        self.engine.diagnose(diag, node: syntax) {
          for i in leftoverStart..<syntax.count {
            $0.note(.ignoringExcessPattern, node: syntax[i])
          }
        }
      }
    }
    func openPatternVarsIntoScope(_ p: DeclaredPattern) -> Bool {
      switch p {
      case .wild, .absurd:
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

  private func scopeCheckEmptyDataDecl(
    _ syntax: EmptyDataDeclSyntax) -> [Decl] {
    typealias ScopeCheckType = (Expr, [ArgumentPlicity])
    let (type, plicity) = self.underScope { (_) -> ScopeCheckType in
      let params = syntax.typedParameterList.map(self.scopeCheckParameter)
      let rebindExpr = self.reparseExpr(syntax.typeIndices.indexExpr)
      let (type, _, plicity)
        = self.rollPi(params, self.scopeCheckExpr(rebindExpr))
      return (type, plicity)
    }

    let dataName = Name(name: syntax.dataIdentifier)
    guard
      let boundDataName = self.bindDefinition(named: dataName, plicity)
      else {
        // If this declaration does not have a unique name, diagnose it and
        // recover by ignoring it.
        self.engine.diagnose(.nameShadows(dataName), node: syntax)
        return []
    }

    return [Decl.dataSignature(TypeSignature(name: boundDataName,
                                             type: type,
                                             plicity: plicity))]
  }

  private func scopeCheckDataDecl(_ syntax: DataDeclSyntax) -> [Decl] {
    return self.underScope { (parentScope) -> [Decl] in
      let params = syntax.typedParameterList.map(self.scopeCheckParameter)
      let rebindExpr = self.reparseExpr(syntax.typeIndices.indexExpr)
      let (type, names, plicity)
        = self.rollPi(params, self.scopeCheckExpr(rebindExpr))
      let dataName = Name(name: syntax.dataIdentifier)
      guard
        let boundDataName = self.bindDefinition(named: dataName,
                                                in: parentScope, plicity)
      else {
        // If this declaration does not have a unique name, diagnose it and
        // recover by ignoring it.
        self.engine.diagnose(.nameShadows(dataName), node: syntax)
        return []
      }
      let asc = Decl.dataSignature(TypeSignature(name: boundDataName,
                                                 type: type,
                                                 plicity: plicity))

      let cs = self.underScope(named: boundDataName) { _ in
        return syntax.constructorList.flatMap(self.scopeCheckConstructor)
      }

      for constr in cs {
        guard self.bindConstructor(named: constr.name,
                                   in: parentScope, plicity) != nil else {
          fatalError("Constructor names should be unique by now!")
        }
      }

      return [ asc, Decl.data(boundDataName, names, cs) ]
    }
  }

  private func scopeCheckRecordDecl(_ syntax: RecordDeclSyntax) -> [Decl] {
    let recName = Name(name: syntax.recordName)
    // FIXME: Compute plicity
    guard let boundDataName = self.bindDefinition(named: recName, []) else {
      // If this declaration does not have a unique name, diagnose it and
      // recover by ignoring it.
      self.engine.diagnose(.nameShadows(recName), node: syntax)
      return []
    }
    typealias ScopeCheckType =
      (TypeSignature, Name, [DeclaredField], [Name], [Decl], [ArgumentPlicity])
    let checkedData = self.underScope {_ -> ScopeCheckType? in
      let params = syntax.parameterList.map(self.scopeCheckParameter)
      let indices = self.reparseExpr(syntax.typeIndices.indexExpr)
      let checkedIndices = self.scopeCheckExpr(indices)

      var preSigs = [DeclaredField]()
      var decls = [Decl]()
      var constr: Name?
      for re in self.reparseDecls(syntax.recordElementList) {
        if
          let field = re as? FieldDeclSyntax,
          let checkedField = self.scopeCheckFieldDecl(field)
        {
          preSigs.append(checkedField)
          continue
        }

        if let funcField = re as? ReparsedFunctionDeclSyntax {
          decls.append(contentsOf: self.scopeCheckDecl(funcField))
          continue
        }

        if let recConstr = re as? RecordConstructorDeclSyntax {
          constr = Name(name: recConstr.constructorName)
          continue
        }
      }
      guard let recConstr = constr else {
        self.engine.diagnose(.recordMissingConstructor(boundDataName),
                             node: syntax)
        return nil
      }

      let (ty, names, plicity) = self.rollPi(params, checkedIndices)
      let recordSignature = TypeSignature(name: boundDataName,
                                          type: ty, plicity: plicity)
      return (recordSignature, recConstr, preSigs, names, decls, plicity)
    }

    guard
      let (sig, recConstr, declFields, paramNames, decls, plicity) = checkedData
    else {
      return []
    }

    // Open the record projections into the current scope.
    var sigs = [TypeSignature]()
    for declField in declFields {
      guard let bindName = self.bindProjection(named: declField.name) else {
        // If this declaration does not have a unique name, diagnose it and
        // recover by ignoring it.
        self.engine.diagnose(.nameShadows(declField.name),
                             node: declField.syntax)
        continue
      }
      sigs.append(TypeSignature(name: bindName, type: declField.type,
                                plicity: declField.plicity))
    }

    let fqn = self.activeScope.qualify(name: recConstr)
    guard let bindName = self.bindConstructor(named: fqn, plicity) else {
      // If this declaration does not have a unique name, diagnose it and
      // recover by ignoring it.
      self.engine.diagnose(.nameShadows(recConstr), node: recConstr.syntax)
      return []
    }
    let asc = Decl.recordSignature(sig, bindName)
    let recordDecl: Decl = .record(boundDataName, paramNames,
                                   bindName, sigs)
    return [asc, recordDecl] + decls
  }

  private func scopeCheckFieldDecl(
    _ syntax: FieldDeclSyntax) -> DeclaredField? {
    assert(syntax.ascription.boundNames.count == 1)
    let (ascExpr, plicity) = self.underScope { _ -> (Expr, [ArgumentPlicity]) in
      let rebindExpr = self.reparseExpr(syntax.ascription.typeExpr)
      let plicity = self.computePlicity(rebindExpr)
      let ascExpr = self.scopeCheckExpr(rebindExpr)
      return (ascExpr, plicity)
    }
    let name = Name(name: syntax.ascription.boundNames[0])
    guard self.bindVariable(named: name) != nil else {
      // If this declaration does not have a unique name, diagnose it and
      // recover by ignoring it.
      self.engine.diagnose(.nameShadows(name), node: syntax.ascription)
      return nil
    }
    return DeclaredField(syntax: syntax, name: name,
                         type: ascExpr, plicity: plicity)
  }

  private func scopeCheckConstructor(
    _ syntax: ConstructorDeclSyntax) -> [TypeSignature] {
    var result = [TypeSignature]()
    result.reserveCapacity(syntax.ascription.boundNames.count)
    for synName in syntax.ascription.boundNames {
      let name = Name(name: synName)

      let rebindExpr = self.reparseExpr(syntax.ascription.typeExpr)
      let ascExpr = self.scopeCheckExpr(rebindExpr)
      let plicity = self.computePlicity(rebindExpr)

      let fqn = self.activeScope.qualify(name: name)
      guard let bindName = self.bindConstructor(named: fqn, plicity) else {
        // If this declaration does not have a unique name, diagnose it and
        // recover by ignoring it.
        self.engine.diagnose(.nameShadows(name), node: syntax.ascription)
        continue
      }

      result.append(TypeSignature(name: bindName,
                                  type: ascExpr, plicity: plicity))
    }
    return result
  }

  private func scopeCheckFunctionDecl(
    _ syntax: ReparsedFunctionDeclSyntax) -> [Decl] {
    precondition(syntax.ascription.boundNames.count == 1)

    let rebindExpr = self.reparseExpr(syntax.ascription.typeExpr)
    let ascExpr = self.underScope { _ in
      return self.scopeCheckExpr(rebindExpr)
    }
    let plicity = self.computePlicity(rebindExpr)
    let name = Name(name: syntax.ascription.boundNames[0])
    guard let functionName = self.bindDefinition(named: name, plicity) else {
      fatalError("Should have unique function names by now")
    }
    let ascription = TypeSignature(name: functionName,
                                   type: ascExpr, plicity: plicity)
    let clauses = syntax.clauseList.map({ clause in
      return self.scopeCheckFunctionClause(clause, plicity)
    })
    let fn = Decl.function(functionName, clauses)
    return [Decl.ascription(ascription), fn]
  }

  private func computePlicity(_ syntax: ExprSyntax) -> [ArgumentPlicity] {
    var plicities = [ArgumentPlicity]()
    func go(_ syntax: ExprSyntax) {
      switch syntax {
      case let syntax as ReparsedApplicationExprSyntax:
        let headExpr = syntax.head
        let n = QualifiedName(ast: headExpr.name)
        guard n.string == NewNotation.arrowNotation.name.string else {
          return
        }
        assert(syntax.exprs.count == 2)
        if let piParams = syntax.exprs[0] as? TypedParameterGroupExprSyntax {
          for param in piParams.parameters {
            switch param {
            case let itps as ImplicitTypedParameterSyntax:
              for _ in itps.ascription.boundNames {
                plicities.append(.implicit)
              }
            case let etps as ExplicitTypedParameterSyntax:
              for _ in etps.ascription.boundNames {
                plicities.append(.explicit)
              }
            default:
              fatalError()
            }
          }
        } else {
          plicities.append(.explicit)
        }
        go(syntax.exprs[1])
      case let paren as ParenthesizedExprSyntax:
        go(paren.expr)
      default:
        return
      }
    }
    _ = go(syntax)
    return plicities
  }

  private func scopeCheckFunctionClause(
    _ syntax: FunctionClauseDeclSyntax, _ plicity: [ArgumentPlicity]
  ) -> DeclaredClause {
    switch syntax {
    case let syntax as NormalFunctionClauseDeclSyntax:
      return self.underScope { _ in
        let pattern = self.scopeCheckPattern(syntax.basicExprList, plicity)
        return self.underScope { _ in
          let wheres = self.scopeCheckWhereClause(syntax.whereClause)
          let reparsedRHS = self.reparseExpr(syntax.rhsExpr)
          let body = self.scopeCheckExpr(reparsedRHS)
          return DeclaredClause(patterns: pattern, body: .body(body, wheres))
        }
      }
    case let syntax as WithRuleFunctionClauseDeclSyntax:
      return self.underScope { _ in
        let pattern = self.scopeCheckPattern(syntax.basicExprList, plicity)
        return self.underScope { _ in
          let wheres = self.scopeCheckWhereClause(syntax.whereClause)
          let body = self.scopeCheckExpr(syntax.rhsExpr)
          // FIXME: Introduce the with variables binding too.
          return DeclaredClause(patterns: pattern, body: .body(body, wheres))
        }
      }
    case let syntax as AbsurdFunctionClauseDeclSyntax:
      return self.underScope { _ in
        let pattern = self.scopeCheckPattern(syntax.basicExprList, plicity,
                                             expectAbsurd: true)
        return DeclaredClause(patterns: pattern, body: .empty)
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
    case let syntax as AbsurdExprSyntax:
      return [.absurd(syntax)]
    case let syntax as NamedBasicExprSyntax:
      let headName = QualifiedName(ast: syntax.name).name
      let localName = self.lookupLocalName(headName)
      guard case let .some((_, .constructor(overloadSet))) = localName else {
        return [.variable(headName)]
      }
      return [.constructor(overloadSet.map { $0.0 }, [])]
    case let syntax as ApplicationExprSyntax:
      guard
        let firstExpr = syntax.exprs.first,
        let head = firstExpr as? NamedBasicExprSyntax
      else {
        fatalError("Can't handle this kind of pattern")
      }
      let argsExpr = syntax.exprs.dropFirst().flatMap(self.exprToDeclPattern)
      let headName = QualifiedName(ast: head.name).name
      let localName = self.lookupLocalName(headName)
      guard case let .some((_, .constructor(overloadSet))) = localName else {
        fatalError()
      }
      return [.constructor(overloadSet.map { $0.0 }, argsExpr)]
    case let syntax as ReparsedApplicationExprSyntax:
      let name = QualifiedName(ast: syntax.head.name).name
      let lookupResult = self.lookupLocalName(name)
      guard case let .some(_, .constructor(overloadSet)) = lookupResult else {
        return self.exprToDeclPattern(syntax.head)
             + syntax.exprs.flatMap(self.exprToDeclPattern)
      }
      return [.constructor(overloadSet.map { $0.0 },
                           syntax.exprs.flatMap(self.exprToDeclPattern))]
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
  func reparseDecls(_ ds: DeclListSyntax,
                    allowOmittingSignatures: Bool = false) -> DeclListSyntax {
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
        if clauseMap[name] == nil {
          if allowOmittingSignatures {
            let bindingDecl = SyntaxFactory.makeLetBindingDecl(
                head: SyntaxFactory.makeNamedBasicExpr(name: SyntaxFactory.makeQualifiedNameSyntax([
                  SyntaxFactory.makeQualifiedNamePiece(name: name.syntax, trailingPeriod: nil)
                ])),
                basicExprList: lhs,
                equalsToken: funcDecl.equalsToken,
                boundExpr: funcDecl.rhsExpr,
                trailingSemicolon: funcDecl.trailingSemicolon)
            decls.append(bindingDecl)
            continue
          } else {
            self.engine.diagnose(.bodyBeforeSignature(name), node: funcDecl)
            continue
          }
        }
        clauseMap[name]!.append(reparsedDecl)
      case let funcDecl as AbsurdFunctionClauseDeclSyntax:
        let (name, lhs) = self.reparseLHS(funcDecl.basicExprList)
        let reparsedDecl = funcDecl.withBasicExprList(lhs)
        guard clauseMap[name] != nil else {
          self.engine.diagnose(.bodyBeforeSignature(name), node: funcDecl)
          continue
        }
        clauseMap[name]!.append(reparsedDecl)
      case let fieldDecl as FieldDeclSyntax:
        for synName in fieldDecl.ascription.boundNames {
          let singleAscript = fieldDecl.ascription
                .withBoundNames(SyntaxFactory.makeIdentifierListSyntax([synName]))
          let newField = SyntaxFactory.makeFieldDecl(
            fieldToken: fieldDecl.fieldToken,
            ascription: singleAscript,
            trailingSemicolon: fieldDecl.trailingSemicolon)
          decls.append(newField)
        }
      default:
        decls.append(decl)
      }
    }

    for k in nameList {
      let function = funcMap[k]!
      let clauses = clauseMap[k]!
      let singleton = SyntaxFactory.makeIdentifierListSyntax([ k.syntax ])
      decls.append(SyntaxFactory.makeReparsedFunctionDecl(
        ascription: function.ascription.withBoundNames(singleton),
        trailingSemicolon: function.trailingSemicolon,
        clauseList: SyntaxFactory.makeFunctionClauseListSyntax(clauses)))
    }

    return SyntaxFactory.makeDeclListSyntax(decls)
  }

  private func scopeCheckFixityDecl(_ syntax: FixityDeclSyntax) -> [Decl] {
    _ = fixityFromSyntax(syntax, diagnose: true)
    return []
  }
}

extension NameBinding {
  fileprivate enum ArgumentConsumptionError {
    case extraneousArguments(expected: Int, have: Int,
                             implicit: Int, leftoverStart: Int)
  }

  /// Consumes arguments of a given plicity and returns an array of all valid
  /// arguments.
  ///
  /// This function may be used to validate both the LHS and RHS of a
  /// declaration.
  ///
  /// Matching parameters is an iterative process that tries to drag as many
  /// implicit arguments into scope as possible as long as they are anchored by
  /// a named argument.  For example, given the declaration:
  ///
  /// ```
  /// f : {A B : Type} -> A -> B -> {C : Type} -> C -> A
  /// f x y c = x
  /// ```
  ///
  /// The parameters `A, B` are dragged into scope by the introduction of `x`,
  /// and `c` drags `C` into scope.  Items implicitly dragged into scope are
  /// represented by the value in the `implicit` parameter; either a wildcard
  /// pattern for LHSes or metavariables for RHSes.
  fileprivate func consumeArguments<C, T>(
    _ syntax: C, _ plicity: [ArgumentPlicity], _ implicit: T,
    _ valuesFn: (C.Element) -> [T], allowExtraneous: Bool = false
  ) -> ([T], ArgumentConsumptionError?)
    where C: Collection, C.Indices.Index == Int {
    var arguments = [T]()
    var lastExplicit = -1
    var syntaxIdx = 0
    var implicitCount = 0
    for i in 0..<plicity.count {
      guard syntaxIdx < syntax.count else {
        for trailingImplIdx in i..<plicity.count {
          guard case .implicit = plicity[trailingImplIdx] else {
            break
          }
          arguments.append(implicit)
        }
        break
      }

      guard case .explicit = plicity[i] else {
        implicitCount += 1
        continue
      }
      if i - lastExplicit - 1 > 0 || (lastExplicit == -1 && i > 0) {
        let extra = (lastExplicit == -1)
                  ? i
                  : (i - lastExplicit - 1)
        let wildCards = repeatElement(implicit,
                                      count: extra)
        arguments.append(contentsOf: wildCards)
      }
      let val = valuesFn(syntax[syntaxIdx])
      arguments.append(contentsOf: val)
      syntaxIdx += 1
      lastExplicit = i
    }
    guard syntaxIdx >= syntax.count || allowExtraneous else {
      let err = ArgumentConsumptionError
        .extraneousArguments(expected: arguments.count, have: syntax.count,
                             implicit: implicitCount, leftoverStart: syntaxIdx)
      return (arguments, err)
    }
    if allowExtraneous && syntaxIdx < syntax.count {
      for i in syntaxIdx..<syntax.count {
        arguments.append(contentsOf: valuesFn(syntax[i]))
      }
    }
    return (arguments, nil)
  }
}

extension NameBinding {
  private func scopeCheckImportDecl(_ syntax: ImportDeclSyntax) -> [Decl] {
    let name = QualifiedName(ast: syntax.importIdentifier)
    guard let dependentURL = self.validateImportName(name) else {
      self.engine.diagnose(.incorrectModuleName(name), node: name.node)
      return []
    }
    guard let importedDecls = self.processImportedFile(dependentURL) else {
      fatalError()
    }
    guard self.importModule(name, importedDecls) else {
      fatalError()
    }
    return []
  }

  private func scopeCheckOpenImportDecl(
    _ syntax: OpenImportDeclSyntax
  ) -> [Decl] {
    let name = QualifiedName(ast: syntax.importIdentifier)
    guard let dependentURL = self.validateImportName(name) else {
      self.engine.diagnose(.incorrectModuleName(name), node: name.node)
      return []
    }
    guard let importedDecls = self.processImportedFile(dependentURL) else {
      fatalError()
    }
    guard self.importModule(name, importedDecls) else {
      fatalError()
    }
    self.bindOpenNames(importedDecls, from: name)
    return []
  }
}
