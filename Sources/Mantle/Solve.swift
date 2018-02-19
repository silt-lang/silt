/// Solve.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho

typealias ConstraintID = UInt
typealias SolverConstraints = [(Set<Meta>, SolverConstraint)]

/// The solve phase uses McBride-Gundry Unification to assign unifiers to
/// metavariables.
///
/// We implement a significantly less powerful form of the Ambulando
/// Solver present in McBride and Gundry's papers and Epigram.
/// Manipulations of the proof context occur as side effecting operations
/// on the signature.  Hence when McBride and Gundry speak of moving
/// "left" or "right" we must instead "strengthen" and "weaken" corresponding
/// substitutions.
///
/// McBride-Gundry unification is complicated and hard to describe, let alone
/// get right.  Nevertheless, we currently implement the following strategies:
///
/// - Intensional (Syntactic) Equality
/// - Eta-expansion and contraction
/// - Rigid-rigid decomposition
/// - Inversion
/// - Intersection
/// - Pruning
///
/// Pientka notes that we ought to try
///
/// - Pruning despite non-linearity.
/// - Flattening Sigmas
/// - Lowering (if we model tuples in TT).
///
/// The goal is to try to reduce a term involving metavariables to one that is
/// in Miller (and Pfenning's) "Pattern Fragment" (where metavariables are
/// applied to spines of distinct bound variables).  Terms in the pattern
/// fragment have a number of desirable properties to a type solver: decidable
/// unification and the presence of most-general unifiers.  However, we are
/// not lucky enough to always be in this state, so the algorithm implements
/// constraint postponement in the hope that we *will* be at some point in the
/// future.
public final class SolvePhaseState {
  var constraintCount: ConstraintID = 0
  var constraints: SolverConstraints = []

  func nextCount() -> UInt {
    self.constraintCount += 1
    return self.constraintCount
  }

  public init() {}
}

extension TypeChecker {
  /// Solves a series of heterogeneous constraints yielding the environment of
  /// the solver when it finishes.
  func solve(_ constraints: [Constraint]) -> Environment {
    let solver = TypeChecker<SolvePhaseState>(self.signature,
                                              self.environment,
                                              SolvePhaseState(),
                                              self.engine,
                                              options)
    for c in constraints {
      solver.solve(c)
    }
    return self.environment
  }
}

/// Implements homogeneous constraints for the solver.
indirect enum SolverConstraint: CustomDebugStringConvertible {
  /// Under the given context, and given that each term has the specified type,
  /// synthesize or check for a common unifier between the two terms.
  case unify(Context, Type<TT>, Term<TT>, Term<TT>)
  /// Under the given context, and given that the type of an application's spine
  /// ultimately has a particular type, check that the elims in the spines of
  /// two terms have a common unifier between them.
  case unifySpines(Context, Type<TT>, Term<TT>?,
                   [Elim<Term<TT>>], [Elim<Term<TT>>])
  /// The conjunction of multiple constraints.
  case conjoin([SolverConstraint])
  /// The hypothetical form of two constraints: If the first constraint is
  /// satisfied, we may move on to the second.  Else we fail the solution set.
  case suppose(SolverConstraint, SolverConstraint)

  // Decomposes a heterogeneous constraint into a homogeneous constraint.
  init(_ c: Constraint) {
    switch c {
    case let .equal(ctx, ty1, t1, ty2, t2):
      self = SolverConstraint.suppose(
        SolverConstraint.unify(ctx, TT.type, ty1, ty2),
        SolverConstraint.unify(ctx, ty1, t1, t2))
    }
  }

  var debugDescription: String {
    switch self {
    case let .unify(_, ty, tm1, tm2):
      return "\(tm1) : \(ty) == \(tm2) : \(ty)"
    case let .suppose(con1, con2):
      return "(\(con1.debugDescription)) => (\(con2.debugDescription))"
    case let .conjoin(cs):
      return cs.map({$0.debugDescription}).joined(separator: " AND ")
    case let .unifySpines(_, ty, mbH, elims1, elims2):
      let desc = zip(elims1, elims2).map({ (e1, e2) in
        return "\(e1) == \(e2)"
      }).joined(separator: " , ")
      return "(\(mbH?.description ?? "??")[\(desc)] : \(ty))"
    }
  }

  var simplify: SolverConstraint? {
    func flatten(sconstraint: SolverConstraint) -> [SolverConstraint] {
      switch sconstraint {
      case let .conjoin(constrs):
        return constrs.flatMap(flatten)
      default:
        return [sconstraint]
      }
    }
    switch self {
    case let .conjoin(xs) where xs.isEmpty:
      return nil
    case let .conjoin(xs) where xs.count == 1:
      return xs.first!.simplify
    case let .conjoin(xs):
      return xs.flatMap(flatten).reduce(nil) { $0 ?? $1.simplify }
    default:
      return self
    }
  }
}

extension TypeChecker where PhaseState == SolvePhaseState {
  func solve(_ c: Constraint) {
    self.state.state.constraints.append(([], SolverConstraint(c)))

    var progress = false
    var newConstr = SolverConstraints()
    while true {
      // Pull out the next candidate constraint and its downstream metas.
      guard let (mvs, constr) = self.state.state.constraints.popLast() else {
        // If we've got no more constraints to solve, check if the last problem
        // generated any more constraints and stick them onto the work queue.
        self.state.state.constraints.append(contentsOf: newConstr)
        if progress {
          newConstr.removeAll()
          progress = false
          continue
        } else {
          return
        }
      }
      /// Attempt to pull out any bindings that may have occured in downstream
      /// metas while we were working on other constraints.
      let mvsBindings = mvs.map(self.signature.lookupMetaBinding)
      let anyNewBindings = mvsBindings.reduce(false) { $0 || ($1 != nil) }
      if mvsBindings.isEmpty || anyNewBindings {
        // If we may make forward progress on this constraint, solve it
        // and return any fresh constraints it generates to the queue.
        let newConstrs = self.solveConstraint(constr)
        newConstr.append(contentsOf: newConstrs)
        progress = true
      } else {
        // Return the constraint to the work queue if we can't make progress on
        // it.
        newConstr.append((mvs, constr))
      }
    }
  }

  /// Attempt to solve a homogeneous constraint returning any new constraints
  /// that may have arisen from the process of doing so.
  private func solveConstraint(_ scon: SolverConstraint) -> SolverConstraints {
    switch scon {
    case let .conjoin(constrs):
      return constrs.flatMap(self.solveConstraint)
    case let .unify(ctx, ty, t1, t2):
      return self.unify((ctx, ty, t1, t2))

    case let .suppose(constr1, constr2):
      let extraConstrs = self.solveConstraint(constr1).flatMap({ (mv, constr) in
        return constr.simplify.map { c in [(mv, c)] }
      }).joined()
      if extraConstrs.isEmpty {
        return self.solveConstraint(constr2)
      }
      let mzero = (Set<Meta>(), SolverConstraint.conjoin([]))
      let (mvs, newAnte) : (Set<Meta>, SolverConstraint)
        = extraConstrs.reduce(mzero) { (acc, next) in
        let (nextSet, nextConstr) = next
        switch (acc.1, nextConstr) {
        case let (.conjoin(cs1), .conjoin(cs2)):
          return (acc.0.union(nextSet), .conjoin(cs1 + cs2))
        case let (.conjoin(cs1), c2):
          return (acc.0.union(nextSet), .conjoin(cs1 + [c2]))
        case let (c1, .conjoin(cs2)):
          return (acc.0.union(nextSet), .conjoin([c1] + cs2))
        case let (c1, c2):
          return (acc.0.union(nextSet), .conjoin([c1, c2]))
        }
      }
      return [(mvs, .suppose(newAnte, constr2))]
    case let .unifySpines(ctx, ty, mbH, elims1, elims2):
      return self.equalSpines(ctx, ty, mbH, elims1, elims2)
    }
  }
}

extension TypeChecker where PhaseState == SolvePhaseState {
  typealias UnifyFrame = (Context, Type<TT>, Term<TT>, Term<TT>)

  enum EqualityProgress {
    case done(SolverConstraints)
    case notDone(UnifyFrame)
  }

  func unify(_ frame: UnifyFrame) -> SolverConstraints {
    let strategies = [
      self.checkEqualTerms,
      self.etaExpandTerms,
      self.interactWithMetas,
    ]
    var args: UnifyFrame  = frame
    for strat in strategies {
      switch strat(args) {
      case let .done(constrs):
        return constrs
      case let .notDone(nextFrame):
        args = nextFrame
      }
    }
    return self.compareTerms(args)
  }

  private func checkEqualTerms(_ frame: UnifyFrame) -> EqualityProgress {
    let (ctx, type, t1, t2) = frame
    let t1Norm = self.toWeakHeadNormalForm(t1).ignoreBlocking
    let t2Norm = self.toWeakHeadNormalForm(t2).ignoreBlocking
    guard t1Norm == t2Norm else {
      return EqualityProgress.notDone((ctx, type, t1Norm, t2Norm))
    }
    return EqualityProgress.done([])
  }

  private func etaExpandTerms(_ frame: UnifyFrame) -> EqualityProgress {
    let (ctx, type, t1, t2) = frame
    let etaT1 = self.etaExpand(type, t1)
    let etaT2 = self.etaExpand(type, t2)
    return EqualityProgress.notDone((ctx, type, etaT1, etaT2))
  }

  private func interactWithMetas(_ frame: UnifyFrame) -> EqualityProgress {
    let (ctx, type, t1, t2) = frame
    let blockedT1 = self.toWeakHeadNormalForm(t1)
    let t1Norm = blockedT1.ignoreBlocking
    let blockedT2 = self.toWeakHeadNormalForm(t2)
    let t2Norm = blockedT2.ignoreBlocking
    switch (blockedT1, blockedT2) {
    case let (.onHead(mv1, els1), .onHead(mv2, els2)) where mv1 == mv2:
      guard self.tryIntersection(mv1, els1, els2) else {
        return EqualityProgress.done([])
      }
      return EqualityProgress.done([([mv1], .unify(ctx, type, t1Norm, t2Norm))])
    case let (.onHead(mv, elims), _):
      return EqualityProgress.done(self.bindMeta(in: ctx, type, mv, elims, t2))
    case let (_, .onHead(mv, elims)):
      return EqualityProgress.done(self.bindMeta(in: ctx, type, mv, elims, t1))
    case (.notBlocked(_), .notBlocked(_)):
      return EqualityProgress.notDone((ctx, type, t1Norm, t2Norm))
    default:
      print(blockedT1, blockedT2)
      fatalError()
    }
  }

  private func bindMeta(
    in ctx: Context, _ type: Type<TT>, _ meta: Meta,
    _ elims: [Elim<Term<TT>>], _ term: Term<TT>
  ) -> SolverConstraints {
    let inversionResult = self.invert(elims)
    guard case let .success(inv) = inversionResult else {
      guard case let .failure(mvs) = inversionResult else { fatalError() }

      let fvs = self.freeVars(term).all
      guard let prunedMeta = self.tryPruneSpine(fvs, meta, elims) else {
        let metaTerm = TT.apply(.meta(meta), elims)
        return [(mvs.union([meta]), .unify(ctx, type, metaTerm, term))]
      }
      let elimedMeta = self.eliminate(prunedMeta, elims)
      return self.unify((ctx, type, elimedMeta, term))
    }

    let prunedTerm = self.pruneTerm(Set(inv.substitution.map {$0.0}), term)
    switch self.applyInversion(inv, to: prunedTerm, in: ctx) {
    case let .success(mvb):
      // FIXME: This binding cannot occur unless we perform the occurs check.
      // We need to compute the metas present in the binding and check that
      // the current meta isn't in there.
      self.signature.instantiateMeta(meta, mvb)
      return []
    case let .failure(.collect(mvs)):
      let mvT = TT.apply(.meta(meta), elims)
      return [(mvs, .unify(ctx, type, mvT, term))]
    case let .failure(.fail(v)):
      fatalError("Free variable in term! \(v)")
    }
  }

  private func compareTerms(_ frame: UnifyFrame) -> SolverConstraints {
    let (ctx, type, tm1, tm2) = frame
    let typeView = self.toWeakHeadNormalForm(type).ignoreBlocking
    let t1View = self.toWeakHeadNormalForm(tm1).ignoreBlocking
    let t2View = self.toWeakHeadNormalForm(tm2).ignoreBlocking
    switch (typeView, t1View, t2View) {
    case (.type, .type, .type):
      return []
    case let (.apply(.definition(_), typeParameters),
              .constructor(constr1, constrArgs1),
              .constructor(constr2, constrArgs2)):
      guard constr1 == constr2 else {
        fatalError("Created a constraint with mismatched record constructors?")
      }

      guard let applyParams = typeParameters.mapM({ $0.applyTerm }) else {
        fatalError()
      }
      let (_, openedData) = self.getOpenedDefinition(constr1.key)
      guard case let .dataConstructor(_, _, dataConType) = openedData else {
        fatalError()
      }
      // Apply available arguments up to the type of the constructor itself.
      let appliedDataConType = self.openContextualType(dataConType,
                                                       applyParams)
      return self.equalSpines(ctx, appliedDataConType, nil,
                              constrArgs1.map(Elim<TT>.apply),
                              constrArgs2.map(Elim<TT>.apply))
    case let (.pi(dom, cod), .lambda(body1), .lambda(body2)):
      let ctx2 = ctx + [(wildcardName, dom)]
      return self.unify((ctx2, cod, body1, body2))
    case let (_, .apply(head1, elims1), .apply(head2, elims2)):
      guard head1 == head2 else {
        print(typeView, t1View, t2View)
        fatalError("Terms not equal")
      }
      let headTy = self.infer(head1, in: ctx)
      let headTm = TT.apply(head1, [])
      return self.equalSpines(ctx, headTy, headTm, elims1, elims2)
    case let (.type, .pi(dom1, cod1), .pi(dom2, cod2)):
      let piType = { () -> Type<TT> in
        let avar = TT.apply(.variable(Var(wildcardName, 0)), [])
        return TT.pi(.type, .pi(.pi(avar, .type), .type))
      }()
      let cod1p = TT.lambda(cod1)
      let cod2p = TT.lambda(cod2)
      return self.equalSpines(ctx, piType, nil,
                              [dom1, cod1p].map(Elim<TT>.apply),
                              [dom2, cod2p].map(Elim<TT>.apply))
    default:
      print(typeView, t1View, t2View)
      fatalError("Terms not equal")
    }
  }

  private func equalSpines(
    _ ctx: Context, _ ty: Type<TT>, _ h: Term<TT>?,
    _ elims1: [Elim<Term<TT>>], _ elims2: [Elim<Term<TT>>]
  ) -> SolverConstraints {
    guard !(elims1.isEmpty && elims1.isEmpty) else {
      return []
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
        guard case let .pi(domain, codomain) = piType else {
          fatalError()
        }
        let argFrame: UnifyFrame = (ctx, domain, arg1, arg2)
        let unifyFrame = self.unify(argFrame)
        switch try? codomain.applySubstitution(.strengthen(1), self.eliminate) {
        case .none:
          let instCod = codomain
                    .forceApplySubstitution(.instantiate(arg1), self.eliminate)
          let unifyRestOfSpine: SolverConstraint =
            .unifySpines(ctx, instCod, head,
                         [Elim<TT>](elims1.dropFirst(idx)),
                         [Elim<TT>](elims2.dropFirst(idx)))
          return unifyFrame + self.solveConstraint(unifyRestOfSpine)
        case let .some(substCodomain):
          type = substCodomain
          constrs.append(contentsOf: unifyFrame)
        }
      // case let (.project(proj1), .project(proj2)):
      default:
        print(type.description, elims1, elims2)
        fatalError("Spines not equal")
      }
    }
    return constrs
  }
}
