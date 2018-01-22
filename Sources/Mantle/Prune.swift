/// Prune.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho

extension TypeChecker {
  /// Given a set of variables that are allowed to appear in the spine of a
  /// term, attempts to remove variables not appearing in that set - prune them.
  /// Pruning requires all eliminators be applies and that variables eligible
  /// for pruning not appear rigidly.
  ///
  /// Sometimes we encounter a problem involving variables outside the domain
  /// of the spine.  In which case, we know that these variables must be
  /// independent of the parent meta and we may "prune" them from the term.
  ///
  /// For example, `$0[x] == g($1[x, y]) /\ $1[x, 0] == f(x, 0)`.  In this case,
  /// we know `$0` depends only on `x`, hence `$1` may only depend on `x` and we
  /// may prune `y` by introducing the new equation `$2[x] == f(x, 0)`.
  func tryPruneSpine(
    _ allowed: Set<Var>, _ oldMeta: Meta, _ elims: [Elim<Term<TT>>]
  ) -> Term<TT>? {
    guard let args = elims.mapM({$0.applyTerm}) else {
      return nil
    }
    guard let prunes = args.mapM({ self.shouldPrune(allowed, $0) }) else {
      return nil
    }

    guard prunes.reduce(false, { $0 || $1 }) else {
      return nil
    }
    guard let oldMvType = self.signature.lookupMetaType(oldMeta) else {
      return nil
    }

    let (pruneMetaTy, piPrunes) = self.rerollPrunedPi(oldMvType, prunes)
    guard piPrunes.reduce(false, { $0 || $1.index }) else {
      return nil
    }

    let newMeta = self.signature.addMeta(pruneMetaTy, from: nil)
    let vs = zip((0..<piPrunes.count).reversed(), piPrunes).map { (idx, k) in
      return Elim<TT>.apply(TT.apply(.variable(Var(k.name, UInt(idx))), []))
    }
    let body = TT.apply(.meta(newMeta), vs)
    let prunedBinding = Meta.Binding(arity: piPrunes.count, body: body)
    self.signature.instantiateMeta(oldMeta, prunedBinding)
    return prunedBinding.internalize
  }

  func pruneTerm(_ vs: Set<Var>, _ t: Term<TT>) -> Term<TT> {
    func weakenSet(_ s: Set<Var>, _ name: Var) -> Set<Var> {
      return Set(s.map({ $0.weaken(0, by: 1) })).union([name])
    }
    switch self.toWeakHeadNormalForm(t).ignoreBlocking {
    case .type:
      return .type
    case .refl:
      return .refl
    case let .lambda(body):
      let weakBody = self.pruneTerm(weakenSet(vs, Var(wildcardName, 0)),
                                    body)
      return TT.lambda(weakBody)
    case let .pi(domain, codomain):
      return TT.pi(self.pruneTerm(vs, domain),
                   self.pruneTerm(weakenSet(vs, Var(wildcardName, 0)),
                                  codomain))
    case let .equal(type, x, y):
      return TT.equal(self.pruneTerm(vs, type),
                      self.pruneTerm(vs, x), self.pruneTerm(vs, y))
    case let .apply(.meta(mv), elims):
      let mvT = TT.apply(.meta(mv), elims)
      //      let mvTView = self.toWeakHeadNormalForm(self.etaExpandMeta())
      return mvT
    case let .apply(h, elims):
      return TT.apply(h, elims.map { (e) -> Elim<TT>  in
        switch e {
        case let .apply(t2):
          return Elim<TT>.apply(self.pruneTerm(vs, t2))
        case let .project(p):
          return Elim<TT>.project(p)
        }
      })
    case let .constructor(dataCon, args):
      return TT.constructor(dataCon, args.map { self.pruneTerm(vs, $0) })
    }
  }


  /// HACK: Check whether a term standing for a definition is finally stuck.
  ///
  /// Currently, we give only a crude approximation.
  private func isNeutral(_ f: Opened<QualifiedName, TT>) -> Bool {
    switch self.getOpenedDefinition(f.key).1 {
    case .constant(_, .function(_)): return true
    case .constant(_, _): return false
    default:
      fatalError()
    }
  }

  /// Returns whether the term should be pruned if at all possible.
  ///
  /// This function returns `nil` if the pruning process should not continue
  /// because the variable appears rigidly and the constraints have no solution.
  private func shouldPrune(_ vs: Set<Var>, _ t: Term<TT>) -> Bool? {
    switch self.toWeakHeadNormalForm(t).ignoreBlocking {
    case .lambda(_):
      return nil
    case let .constructor(_, args):
      guard let prunes = args.mapM({ self.shouldPrune(vs, $0) }) else {
        return nil
      }
      return prunes.reduce(false, { $0 || $1})
    case let .apply(.definition(f), _):
      guard self.isNeutral(f) else {
        return nil
      }
      let fvs = self.freeVars(t)
      return !fvs.rigid.isSubset(of: vs)
    default:
      let fvs = self.freeVars(t)
      return !fvs.rigid.isSubset(of: vs)
    }
  }
}

extension TypeChecker {
  func rerollPrunedPi(
    _ ty: Type<TT>, _ prunes: [Bool]) -> (Type<TT>, [Named<Bool>]) {
    let (params, terminal) = self.unrollPi(ty)
    var ty = terminal
    var piPrunes = [Named<Bool>]()
    for (param, needsPrune) in zip(params, prunes).reversed() {
      guard needsPrune else {
        ty = TT.pi(param.1, ty)
        piPrunes.append(Named<Bool>(param.0, false))
        continue
      }
      guard
        let substTy = try? ty.applySubstitution(.strengthen(1), self.eliminate)
      else {
        ty = TT.pi(param.1, ty)
        piPrunes.append(Named<Bool>(param.0, false))
        continue
      }
      ty = substTy
      piPrunes.append(Named<Bool>(param.0, true))
    }
    return (ty, piPrunes)
  }
}
