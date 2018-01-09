/// Check.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho

/// The type *checking* phase implements the iterative translation of
/// well-scoped terms to the core type theory of Silt: TT.  At all levels,
/// verification of synthesized and user-provided types is sanity-checked
/// (mostly because dynamic pattern unification is Hard).
public final class CheckPhaseState {
  public init() {}
}

// MARK: Declarations

extension TypeChecker where PhaseState == CheckPhaseState {
  public func checkModule(_ syntax: DeclaredModule) -> Module {
    // First, build up the initial parameter context.
    var paramCtx = Context()
    for (paramNames, synType) in syntax.params {
      for paramName in paramNames {
        let paramType = self.underExtendedEnvironment(paramCtx) {
          return self.checkExpr(synType, TT.type)
        }
        paramCtx.append((paramName, paramType))
      }
    }
    // Next, check all the decls under it.
    let names = self.underExtendedEnvironment(paramCtx) {
      return syntax.decls.map { self.checkDecl($0).key }
    }
    return Module(telescope: paramCtx, inside: Set(names))
  }

  private func checkDecl(_ d: Decl) -> Opened<QualifiedName, TT> {
    return self.underExtendedEnvironment([]) {
      switch d {
      case let .dataSignature(sig):
        return self.checkDataSignature(sig)
      case let .data(name, xs, cs):
        return self.checkData(name, xs, cs)
      case let .postulate(sig):
        return self.checkPostulate(sig)
      case let .ascription(sig):
        return self.checkAscription(sig)
      case let .function(name, clauses):
        return self.checkFunction(name, clauses)
      case let .recordSignature(sig):
        return self.checkRecordSignature(sig)
      case let .record(name, paramNames, conName, fieldSigs):
        return self.checkRecord(name, paramNames, conName, fieldSigs)
      case let .module(mod):
        return self.checkModuleCommon(mod)
      default:
        fatalError()
      }
    }
  }

  private func checkModuleCommon(
    _ syntax: DeclaredModule) -> Opened<QualifiedName, TT> {
    let module = self.checkModule(syntax)
    let context = self.environment.asContext
    self.signature.addModule(module, named: syntax.moduleName, args: context)
    let args = self.environment.forEachVariable { cv in
      return TT.apply(.variable(cv), [])
    }
    return self.openDefinition(syntax.moduleName, args)
  }

  private func checkDataSignature(
                _ sig: TypeSignature) -> Opened<QualifiedName, TT> {
    let elabType = self.checkExpr(sig.type, TT.type)
    // Check that at the end of the expression there is a `Type`.
    let (tel, endType) = self.unrollPi(elabType)
    _ = self.underExtendedEnvironment(tel) {
      self.checkDefinitionallyEqual(self.environment.asContext,
                                    TT.type, endType, TT.type)
    }
    self.signature.addData(named: sig.name,
                           self.environment.asContext, elabType)
    let args = self.environment.forEachVariable { cv in
      return TT.apply(.variable(cv), [])
    }
    return self.openDefinition(sig.name, args)
  }

  private struct CheckedConstructor {
    let name: QualifiedName
    let count: UInt
    let type: Type<TT>
  }

  private func checkData(
    _ typeName: QualifiedName,
    _ telescopeNames: [Name],
    _ tyConSignatures: [TypeSignature]
  ) -> Opened<QualifiedName, TT> {
    // The type is already defined and opened into scope.
    let (openTyName, openTypeDef) = self.getOpenedDefinition(typeName)
    let defType = self.getTypeOfOpenedDefinition(openTypeDef)
    let (dataPars, _) = self.unrollPi(defType, telescopeNames)
    // First, check constructor types under the type parameters of the parent
    // data declaration's type.
    let conTys
      = self.underExtendedEnvironment(dataPars) { () -> [CheckedConstructor] in
      // We need to weaken the opened type up to the number of parameters.
      let weakTy = openTyName.forceApplySubstitution(.weaken(dataPars.count),
                                                     self.eliminate)
      let elimDataTy = self.eliminate(TT.apply(.definition(weakTy), []),
                                      self.forEachVariable(in: dataPars) { v in
        return Elim<TT>.apply(TT.apply(.variable(v), []))
      })

      return tyConSignatures.map { signature in
        return self.checkConstructor(elimDataTy, signature)
      }
    }

    // Now introduce the constructors.
    conTys.forEach { checkedConstr in
      self.signature.addConstructor(named: checkedConstr.name,
                                    toType: openTyName,
                                    checkedConstr.count,
                                    Contextual(telescope: dataPars,
                                               inside: checkedConstr.type))
      _ = self.openDefinition(checkedConstr.name,
                              self.environment.forEachVariable { envVar in
        return TT.apply(.variable(envVar), [])
      })
    }
    return openTyName
  }

  private func checkConstructor(
    _ parentTy: Type<TT>,
    _ sig: TypeSignature
  ) -> CheckedConstructor {
    let dataConType = self.checkExpr(sig.type, TT.type)
    let (conTel, endType) = self.unrollPi(dataConType)
    self.underExtendedEnvironment(conTel, { () -> Void in
      let weakTy = parentTy.forceApplySubstitution(.weaken(conTel.count),
                                                   self.eliminate)
      self.checkDefinitionallyEqual(self.environment.asContext,
                                    TT.type, weakTy, endType)
    })
    return CheckedConstructor(name: sig.name,
                              count: UInt(conTel.count), type: dataConType)
  }

  private func checkRecordSignature(
    _ sig: TypeSignature) -> Opened<QualifiedName, TT> {
    let elabType = self.checkExpr(sig.type, TT.type)
    // Check that at the end of the expression there is a `Type`.
    let (tel, endType) = self.unrollPi(elabType)
    _ = self.underExtendedEnvironment(tel) {
      self.checkDefinitionallyEqual(self.environment.asContext,
                                    TT.type, endType, TT.type)
    }

    self.signature.addRecord(named: sig.name,
                             self.environment.asContext, elabType)
    let args = self.environment.forEachVariable { cv in
      return TT.apply(.variable(cv), [])
    }
    return self.openDefinition(sig.name, args)
  }

  private func checkProjections(
    _ tyCon: Opened<QualifiedName, TT>,
    _ tyConPars: Telescope<TT>,
    _ fields: [QualifiedName],
    _ fieldTypes: Telescope<TT>
  ) {
    let selfTy = self.eliminate(TT.apply(.definition(tyCon), []),
                                self.forEachVariable(in: tyConPars) { v in
      return Elim<TT>.apply(TT.apply(.variable(v), []))
    })

    let fieldSeq = zip(zip(fields,
                           (0..<fields.count).map(Projection.Field.init)),
                       fieldTypes)
    for ((fld, fldNum), (_, fldTy)) in fieldSeq {
      let endType = TT.pi(selfTy, fldTy)
      self.signature.addProjection(named: fld, index: fldNum, parent: tyCon,
                                   Contextual(telescope: tyConPars,
                                              inside: endType))
    }
  }

  private func checkRecord(
    _ name: QualifiedName,
    _ paramNames: [Name],
    _ conName: QualifiedName,
    _ fieldSigs: [TypeSignature]
  ) -> Opened<QualifiedName, TT> {
    // The type is already defined and opened into scope.
    let (openTyName, openTypeDef) = self.getOpenedDefinition(name)
    let defType = self.getTypeOfOpenedDefinition(openTypeDef)
    let (recPars, _) = self.unrollPi(defType)

    // First, check all the fields to build up a context.
    var fieldsCtx = Context()
    for sig in fieldSigs {
      let fieldType = self.underExtendedEnvironment(fieldsCtx) {
        return self.checkExpr(sig.type, TT.type)
      }
      fieldsCtx.append((Name(name: sig.name.node), fieldType))
    }
    // We need to weaken the opened type up to the number of parameters.
    let weakTy = openTyName.forceApplySubstitution(.weaken(recPars.count),
                                                   self.eliminate)
    let elimDataTy = self.eliminate(TT.apply(.definition(weakTy), []),
                                    self.forEachVariable(in: recPars) { v in
      return Elim<TT>.apply(TT.apply(.variable(v), []))
    })

    // Next, check the projections.
    self.checkProjections(openTyName, recPars,
                          fieldSigs.map { $0.name }, fieldsCtx)

    // Finally, introduce the constructor.
    let weakDataTy = elimDataTy.forceApplySubstitution(.weaken(fieldsCtx.count),
                                                       self.eliminate)
    let conType
      = self.rollPi(in: fieldsCtx, final: weakDataTy)
    self.signature.addConstructor(named: conName, toType: openTyName,
                                  UInt(fieldSigs.count),
                                  Contextual(telescope: recPars,
                                             inside: conType))

    return self.openDefinition(conName, self.environment.forEachVariable { cv in
      return TT.apply(.variable(cv), [])
    })
  }

  func checkDefinitionallyEqual(
    _ ctx: Context,
    _ type: Type<TT>,
    _ t1: Term<TT>,
    _ t2: Term<TT>
  ) {
    guard t1 != t2 else {
      return
    }

    let normT1 = self.toWeakHeadNormalForm(t1).ignoreBlocking
    let normT2 = self.toWeakHeadNormalForm(t2).ignoreBlocking
    guard normT1 != normT2 else {
      return
    }

    return self.compareTerms((ctx, type, normT1, normT2))
  }

  private func checkEqualSpines(
    _ ctx: Context, _ ty: Type<TT>, _ h: Term<TT>?,
    _ elims1: [Elim<Term<TT>>], _ elims2: [Elim<Term<TT>>]
  ) {
    guard !(elims1.isEmpty && elims1.isEmpty) else {
      return
    }
    guard elims1.count == elims2.count else {
      print(ty.description, elims1, elims2)
      fatalError("Spines not equal")
    }

    var type = ty
    var head = h
    var constrs = SolverConstraints()
    var idx = 1
    for (elim1, elim2) in zip(elims1, elims2) {
      defer { idx += 1 }
      switch (elim1, elim2) {
      case let (.apply(arg1), .apply(arg2)):
        let piType = self.toWeakHeadNormalForm(type).ignoreBlocking
        guard case let .pi(dom, cod) = piType else {
          fatalError()
        }
        self.checkDefinitionallyEqual(ctx, dom, arg1, arg2)
        type = cod.forceApplySubstitution(.instantiate(arg1), self.eliminate)
        head = head.map { self.eliminate($0, [.apply(arg1)]) }
      default:
        print(type.description, elims1, elims2)
        fatalError("Spines not equal")
      }
    }
  }

  private func compareTerms(_ frame: UnifyFrame) {
    let (ctx, type, tm1, tm2) = frame
    let typeView = self.toWeakHeadNormalForm(type).ignoreBlocking
    let t1View = self.toWeakHeadNormalForm(tm1).ignoreBlocking
    let t2View = self.toWeakHeadNormalForm(tm2).ignoreBlocking
    switch (typeView, t1View, t2View) {
    case (.type, .type, .type):
      return
    case let (.pi(dom, cod), .lambda(body1), .lambda(body2)):
      let name = TokenSyntax(.identifier("_")) // FIXME: Try harder, maybe
      let ctx2 = [(Name(name: name), dom)] + ctx
      return self.checkDefinitionallyEqual(ctx2, cod, body1, body2)
    case let (_, .apply(h1, elims1), .apply(h2, elims2)):
      guard h1 == h2 else {
        fatalError("Terms not equal")
      }
      let hType = self.infer(h1, in: ctx)
      return self.checkEqualSpines(ctx, hType, TT.apply(h1, []), elims1, elims2)
    default:
      print(typeView, t1View, t2View)
      fatalError("Terms not equal")
    }
  }

  private func checkPostulate(
    _ sig: TypeSignature) -> Opened<QualifiedName, TT> {
    let type = self.checkExpr(sig.type, TT.type)
    self.signature.addPostulate(named: sig.name,
                                self.environment.asContext, type)
    return self.openDefinition(sig.name,
                               self.environment.forEachVariable { envVar in
      return TT.apply(.variable(envVar), [])
    })
  }

  private func checkAscription(
    _ sig: TypeSignature) -> Opened<QualifiedName, TT> {
    let type = self.checkExpr(sig.type, TT.type)
    self.signature.addAscription(named: sig.name,
                                 self.environment.asContext, type)
    return self.openDefinition(sig.name,
                               self.environment.forEachVariable { envVar in
      return TT.apply(.variable(envVar), [])
    })
  }

  func checkPatterns(
    _ patterns: [DeclaredPattern], _ ty: Type<TT>) -> ([Pattern], Type<TT>) {
    var type = self.toWeakHeadNormalForm(ty).ignoreBlocking
    var pats = [Pattern]()
    for pattern in patterns {
      switch type {
      case let .pi(domain, codomain):
        let (pat, nextType) = self.checkPattern(pattern, domain, codomain)
        type = self.toWeakHeadNormalForm(nextType).ignoreBlocking
        pats.append(pat)
      default:
        fatalError()
      }
    }
    return (pats, type)
  }

  func checkPattern(
    _ synPat: DeclaredPattern, _ patType: Type<TT>, _ type: Type<TT>
  ) -> (Pattern, Term<TT>) {
    switch synPat {
    case let .variable(name):
      // The type is already scoped over a single variable, so we're fine.
      self.extendEnvironment([(name, patType)])
      return (.variable, type)
    case .wild:
      let name = TokenSyntax(.identifier("_")) // FIXME: Try harder, maybe
      self.extendEnvironment([(Name(name: name), patType)])
      return (.variable, type)
    case let .constructor(dataCon, synPats):
      // Use the data constructor to locate back up the parent so we can
      // retrieve its argument telescope.
      guard let data = self.signature.lookupDefinition(dataCon) else {
        fatalError()
      }
      guard case let .dataConstructor(tyCon, _, _) = data.inside else {
        fatalError()
      }
      guard let ty = self.signature.lookupDefinition(tyCon) else {
        fatalError()
      }

      // Check that we've got only data.
      switch ty.inside {
      case .constant(_, .data(_)):
        break
      case .constant(_, .record(_, _)):
        // FIXME: Should be a diagnostic.
        fatalError("Can't pattern match on record")
      default:
        fatalError("General syntax failure??")
      }

      // Next, try to pull out the matching pattern type which should be the
      // parent type of the constructor.
      switch self.toWeakHeadNormalForm(patType).ignoreBlocking {
      case let .apply(.definition(patternCon), arguments)
        where tyCon == patternCon.key:
        guard let tyConArgs = arguments.mapM({ $0.applyTerm }) else {
          fatalError()
        }
        // Next, open the constructor type and apply any parameters on the
        // parent data decl.
        let openDataCon = Opened(dataCon, patternCon.args)
        let contextDef = self.openContextualDefinition(data, patternCon.args)
        guard case let .dataConstructor(_, _, dataConType) = contextDef else {
          fatalError()
        }
        // Apply available arguments up to the type of the constructor itself.
        let appliedDataConType = self.openContextualType(dataConType, tyConArgs)
        let (telescope, _) = self.unrollPi(appliedDataConType)
        let teleSeq = zip((0..<telescope.count).reversed(), telescope)
        let t = TT.constructor(openDataCon, teleSeq.map { (i, t) in
          let (nm, _) = t
          return TT.apply(.variable(Var(nm, UInt(i))), [])
        })
        // Now weaken the opened type up to the parameters we're
        // going to open into scope.
        let numDataConArgs = telescope.count
        let rho = Substitution.instantiate(t)
                              .compose(.lift(1, .weaken(numDataConArgs)))
        let substType = type.forceApplySubstitution(rho, self.eliminate)
        let innerPatType = self.rollPi(in: telescope, final: substType)
        // And check the inner patterns against it.
        let (pats, retTy) = self.checkPatterns(synPats, innerPatType)
        return (.constructor(openDataCon, pats), retTy)
      case .apply(.definition(_), _):
        // FIXME: Should be a diagnostic.
        fatalError("Pattern type does not match parent type of constructor")
      default:
        fatalError()
      }
      print(dataCon, synPats)
      fatalError()
    }
  }

  func checkClause(_ ty: Type<TT>, _ clause: DeclaredClause) -> Clause {
    let (pats, type) = self.checkPatterns(clause.patterns, ty)
    return self.underExtendedEnvironment([]) {
      switch clause.body {
      case .empty:
        // FIXME: Implement absurd patterns.
        fatalError("")
      case let .body(body, _ /*whereDecls*/):
        let body = self.checkExpr(body, type)
        return Clause(pattern: pats, body: body)
      }
    }
  }

  func checkFunction(
    _ name: QualifiedName, _ clauses: [DeclaredClause]
  ) -> Opened<QualifiedName, TT> {
    let (fun, funDef) = self.getOpenedDefinition(name)
    switch funDef {
    case let .constant(ty, .function(.open)):
      let clauses = clauses.map { clause in
        return self.underNewScope { self.checkClause(ty, clause) }
      }
      let inv = self.inferInvertibility(clauses)
      self.signature.addFunctionClauses(fun, inv)
      return fun
    case .constant(_, .postulate):
      fatalError("Cannot give body to postulate")
    default:
      fatalError()
    }
  }
}

// MARK: Expressions

extension TypeChecker where PhaseState == CheckPhaseState {
  func checkExpr(_ syntax: Expr, _ ty: Type<TT>) -> Term<TT> {
    return self.underExtendedEnvironment([]) {
      let (elabTm, constraints) = self.elaborate(ty, syntax)
      print("=========UNSOLVED CONSTRAINTS=========")
      for c in constraints {
        print(c)
      }
      print("======================================")
      let solvedEnv = self.solve(constraints)
      self.checkTT(elabTm, hasType: ty, in: solvedEnv.asContext)
      return elabTm
    }
  }
}

// MARK: Type Theory

extension TypeChecker where PhaseState == CheckPhaseState {
  func checkTT(_ term: Term<TT>, hasType type: Type<TT>, in ctx: Context) {
    switch term {
    case let .constructor(tyCon, args):
//    let contextDef = self.signature.lookupDefinition(tyCon.key)!
//    let openedDef = self.openDefinition(contextDef, tyCon.args)
//    guard case let .dataConstructor(tyCon, _, dataConType) = openedDef else {
//      fatalError()
//    }
      print(tyCon)
      print(args)
      fatalError()
    case .refl:
      guard case let .equal(eqTy, lhs, rhs) = type else {
        fatalError()
      }
      return self.checkDefinitionallyEqual(ctx, eqTy, lhs, rhs)
    case let .lambda(body):
      guard case let .pi(domain, codomain) = type else {
        fatalError()
      }
      let name = TokenSyntax(.identifier("_")) // FIXME: Try harder, maybe
      return self.checkTT(body,
                          hasType: codomain,
                          in: [(Name(name: name), domain)] + ctx)
    default:
      let infType = self.infer(term, in: ctx)
      return self.checkDefinitionallyEqual(ctx, TT.type, infType, type)
    }
  }
}
