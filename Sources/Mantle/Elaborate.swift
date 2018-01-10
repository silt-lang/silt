/// Elaborate.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho

/// The elaboration phase lowers well-scoped syntactic forms to core type theory
/// terms.  Along the way, elaboration generates metavariables and
/// heterogeneous equality constraints between terms that can be solved by
/// the solving phase to yield unifiers for terms.
///
/// Elaboration preserves the (rough) structure of terms, even malformed ones.
final class ElaboratePhaseState {
  var constraints: [Constraint] = []
}

extension TypeChecker {
  func elaborate(_ ty: Type<TT>, _ expr: Expr) -> (Term<TT>, [Constraint]) {
    let elaborator = TypeChecker<ElaboratePhaseState>(self.signature,
                                                      self.environment,
                                                      ElaboratePhaseState(),
                                                      options)
    let ttExpr = elaborator.elaborate(expr, expecting: ty)
    return (ttExpr, elaborator.state.state.constraints)
  }
}

/// A heterogeneous equality constraint between two types and two terms.
///
/// Constraints must be heterogeneous because it is possible to generate
/// equations between terms where some non-obvious amount of reduction must
/// be performed on either the types or the terms to satisfy the equality.
/// However, expansion by the solver follows the so-called "heterogeneity
/// invariant" - every heterogeneous equation will break down into constraints
/// that imply homogeneous equality of types and terms.
enum Constraint: CustomDebugStringConvertible {
  /// Given a context, (T1 : Type), (t1 : T1), (T2 : Type) and (t2 : T2),
  /// forms the constraint (t1 : T1) == (t2 : T2).
  case equal(Context, Type<TT>, Term<TT>, Type<TT>, Term<TT>)

  var debugDescription: String {
    switch self {
    case let .equal(_, ty1, tm1, ty2, tm2):
      return "\(tm1) : \(ty1) == \(tm2) : \(ty2)"
    }
  }
}

extension TypeChecker where PhaseState == ElaboratePhaseState {
  // Elaborate a scope-checked syntax term into Type Theory.
  func elaborate(_ syntax: Expr, expecting exType: Type<TT>) -> Term<TT> {
    switch syntax {
    // FIXME: Impredicative garbage.
    //
    // -----------------
    //   Γ ⊢ Type : Type
    //
    // Actual rule should be
    //
    // -----------------
    //   Γ ⊢ Type(i) : Type(i+1)
    case .type:
      return self.expect(exType, TT.type, TT.type, from: syntax)

    //   α : Γ → T ∈ Σ
    // -----------------
    //   Γ ⊢ α Γ : T
    case .meta:
      return self.addMeta(in: self.environment.asContext,
                          from: syntax, expect: exType)

    //   Γ ⊢ S : Type    Γ, x : S ⊢ T: Type
    // -------------------------------------
    //        Γ ⊢ (x : S) → T: Type
    case let .pi(name, domain, codomain):
      let elabDomain = self.elaborate(domain, expecting: TT.type)
      let t = self.underExtendedEnvironment([(name, elabDomain)]) { () -> TT in
        let elabCodomain = self.elaborate(codomain, expecting: TT.type)
        return TT.pi(elabDomain, elabCodomain)
      }
      return self.expect(exType, TT.type, t, from: syntax)
    // Just lift non-dependent function spaces to dependent ones.
    case let .function(domain, codomain):
      let name = TokenSyntax(.identifier("_")) // FIXME: Try harder, maybe
      return self.elaborate(.pi(Name(name: name), domain, codomain),
                            expecting: exType)

    //       Γ, x : A ⊢ t : B
    // -----------------------------
    //   Γ ⊢ λ x -> t : (x: A) → B
    case let .lambda((name, ty), lamBody):
      let elabTy = self.elaborate(ty, expecting: TT.type)
      let dom = self.addMeta(in: self.environment.asContext,
                             from: ty, expect: elabTy)
      let (cod, body)
            = self.underExtendedEnvironment([(name, dom)]) { () -> (TT, TT) in
        let cod = self.addMeta(in: self.environment.asContext,
                               from: lamBody, expect: TT.type)
        let body = self.elaborate(lamBody, expecting: cod)
        return (cod, body)
      }
      return self.expect(exType, TT.pi(dom, cod), TT.lambda(body), from: syntax)

    //   Γ ⊢ A : Type    Γ ⊢ t : A    Γ ⊢ u : A
    // -------------------------------------------
    //               Γ ⊢ t ≡_A u : Type
    case let .equal(eqTy, lhsTy, rhsTy):
      let elabEqTy = self.elaborate(eqTy, expecting: TT.type)
      let elabLHS = self.elaborate(lhsTy, expecting: elabEqTy)
      let elabRHS = self.elaborate(rhsTy, expecting: elabEqTy)
      return self.expect(exType, TT.type,
                         TT.equal(elabEqTy, elabLHS, elabRHS), from: syntax)

    //   Γ ⊢ A : Type    Γ ⊢ t : A    Γ ⊢ u : A
    // -----------------------------------------
    //             Γ ⊢ refl : t ≡_A u
    case .refl:
      let ctx = self.environment.asContext
      let eqTy = self.addMeta(in: ctx, from: syntax, expect: TT.type)
      let eqMetaTy = self.addMeta(in: ctx, from: syntax, expect: eqTy)
      return self.expect(exType, TT.equal(eqTy, eqMetaTy, eqMetaTy),
                         TT.refl, from: syntax)

    case let .constructor(dataCon, constructorArgs):
      let (openedCon, dc) = self.getOpenedDefinition(dataCon)
      guard case let .dataConstructor(tyCon, _, dataConType) = dc else {
        fatalError()
      }
      let (_, parentTy) = self.getOpenedDefinition(tyCon.key)
      let dataConTy = self.getTypeOfOpenedDefinition(parentTy)
      let dataConArgs = self.fillPiWithMetas(dataConTy)

      precondition(dataConType.telescope.count == dataConArgs.count)
      let instDataConTy = self.forceInstantiate(dataConType.inside, dataConArgs)
      var appliedConTy = self.toWeakHeadNormalForm(instDataConTy).ignoreBlocking
      var conArgs = [Term<TT>]()
      for arg in constructorArgs {
        guard case let .pi(domain, codomain) = appliedConTy else {
          fatalError()
        }
        let elabArg = self.elaborate(arg, expecting: domain)
        let instCodomain = self.forceInstantiate(codomain, [elabArg])
        appliedConTy = self.toWeakHeadNormalForm(instCodomain).ignoreBlocking
        conArgs.append(elabArg)
      }
      let conTy = TT.apply(.definition(tyCon), dataConArgs.map(Elim<TT>.apply))
      return self.expect(exType, conTy,
                         TT.constructor(openedCon, conArgs), from: syntax)

    case let .apply(h, elims):
      return self.elaborateApp(exType, h, elims.reversed(), syntax)
      /*
      //   Γ ⊢ h ⇒ A
      // ------------------
      //   Γ ⊢ h : A
      let (t, hType) = self.elaborate(h)
      var term = self.expect(exType, hType, t, from: syntax)
      var exTy = exType
      for elim in elims.reversed() {
        switch elim {
        //   Γ ⊢ h es : (x : A) → B    Γ ⊢ u : A
        // --------------------------------------
        //   Γ ⊢ h es u : B[u / x]
        case let .apply(arg):
          let dm = self.addMeta(in: self.environment.asContext,
                                from: arg, expect: TT.type)
          let name = TokenSyntax(.identifier("_")) // FIXME: Try harder, maybe
          let cd = self.underExtendedEnvironment([(Name(name: name), dm)]) {
            return self.addMeta(in: self.environment.asContext,
                                from: arg, expect: TT.type)
          }
          exTy = TT.pi(dm, cd)
          let elabArgTy = self.elaborate(arg, expecting: dm)
          term = self.expect(exTy, self.instantiate(cd, [elabArgTy]),
                             self.eliminate(term, [.apply(elabArgTy)]),
                             from: syntax)
        case .projection(_):
          fatalError()
        }
      }
      return term
 */
    }
  }

  // FIXME: The non-recursive form of this function isn't capable of creating
  // the proper constraints.  We have to push elaborated elims "forward" while
  // pushing an ever-growing pi-type backwards, else we risk expecting the wrong
  // type during elaboration.
  func elaborateApp(
    _ type: Type<TT>, _ head: ApplyHead, _ elims: [Elimination], _ from: Expr
  ) -> Term<TT> {
    guard let first = elims.first, case let .apply(arg) = first else {
      assert(elims.isEmpty)
      let (t, hType) = self.elaborate(head)
      return self.expect(type, hType, t, from: from)
    }
    let dm = self.addMeta(in: self.environment.asContext,
                          from: from, expect: TT.type)
    let name = TokenSyntax(.identifier("_")) // FIXME: Try harder, maybe
    let cd = self.underExtendedEnvironment([(Name(name: name), dm)]) {
      return self.addMeta(in: self.environment.asContext,
                          from: arg, expect: TT.type)
    }
    let pi = TT.pi(dm, cd)
    let elabArgTy = self.elaborate(arg, expecting: dm)
    let f = self.elaborateApp(pi, head, [Elimination](elims.dropFirst()), from)
    return self.expect(type, self.forceInstantiate(cd, [elabArgTy]),
                       self.eliminate(f, [.apply(elabArgTy)]),
                       from: from)
  }

  //   x: A ∈ Γ
  // -------------
  //   Γ ⊢ x ⇒ A
  private func elaborate(_ syntax: ApplyHead) -> (Term<TT>, Type<TT>) {
    switch syntax {
    case let .variable(name):
      guard
        let (v, type) = self.environment.lookupName(name, self.eliminate)
      else {
        fatalError("Scope check is broken?")
      }
      return (TT.apply(.variable(v), []), type)
    case let .definition(name):
      let (defName, openDef) = self.getOpenedDefinition(name)
      return (TT.apply(.definition(defName), []),
              self.getTypeOfOpenedDefinition(openDef))
    }
  }

  // Writes a constraint equating a fresh meta-variable of the given
  // type to the typed term it is given.
  func expect(
    _ expectedType: Type<TT>, _ givenType: Type<TT>,
    _ term: Term<TT>, from node: Expr
  ) -> Term<TT> {
    let ctx = self.environment.asContext
    let t = self.addMeta(in: ctx, from: node, expect: expectedType)
    self.writeConstraint(.equal(ctx, expectedType, t, givenType, term))
    return t
  }

  // Takes a Pi-type and replaces all it's elements with metavariables.
  private func fillPiWithMetas(_ ty: Type<TT>) -> [Term<TT>] {
    var type = self.toWeakHeadNormalForm(ty).ignoreBlocking
    var metas = [Term<TT>]()
    while true {
      switch type {
      case let .pi(domain, codomain):
        let meta = self.addMeta(in: self.environment.asContext, expect: domain)
        let instCodomain = self.forceInstantiate(codomain, [meta])
        type = self.toWeakHeadNormalForm(instCodomain).ignoreBlocking
        metas.append(meta)
      case .type:
        return metas
      default:
        fatalError("Expected Pi")
      }
    }
  }

  private func writeConstraint(_ c: Constraint) {
    self.state.state.constraints.append(c)
  }
}
