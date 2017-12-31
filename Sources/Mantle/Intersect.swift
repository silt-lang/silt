/// Intersect.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

extension TypeChecker {
  /// Attempts to take the intersection of the spines of two equal metavariable
  /// heads and solve it.  Returns true if intersection succeeded in
  /// instantiating a metavariable, or false if not.
  ///
  /// Given that two metavariables are equal, we can attempt to solve for terms
  /// in the spine by taking the intersection of eliminators (assuming they're
  /// all variables themselves).  For example, given a constraint of the form.
  /// `$0[x, y, x, z] == $0[x, y, y, x]` it is immediately clear that the 3rd
  /// and 4th argument are independent of `$0`.  So we solve the new equation
  /// `$0[x, y, z, w] == $1[x, y]` instead.
  func tryIntersection(
    _ mv: Meta, _ elims1: [Elim<TT>], _ elims2: [Elim<TT>]) -> Bool {
    guard let prunes = self.intersectSpines(elims1, elims2) else {
      return false
    }
    let mvType = self.signature.lookupMetaType(mv)!
    let (pruneMetaTy, piPrunes) = self.rerollPrunedPi(mvType,
                                                      prunes.map {$0.index})
    // If we've nothing to intersect, fail.
    guard piPrunes.reduce(false, { $0 || $1.index }) else {
      return false
    }
    let metaTy = self.rollPi(in: self.environment.asContext, final: pruneMetaTy)
    let newMv = self.signature.addMeta(metaTy, from: nil)
    let vs = piPrunes.enumerated().map { (idx, k) in
      return Elim<TT>.apply(TT.apply(.variable(Var(k.name, UInt(idx))), []))
    }
    let binding = Meta.Binding(arity: piPrunes.count,
                              body: TT.apply(.meta(newMv), vs))
    self.signature.instantiateMeta(mv, binding)
    return true
  }

  /// Performs intersection of two spines to produce a list of named pruning
  /// indicators.
  ///
  /// A pruning indicator has value `true` when the variables at that position
  /// are distinct and may be removed.  `false` otherwise.
  func intersectSpines(
    _ elims1: [Elim<TT>], _ elims2: [Elim<TT>]) -> [Named<Bool>]? {
    return zip(elims1, elims2).mapM { (e1, e2) -> Named<Bool>? in
      guard case let .apply(t1) = e1, case let .apply(t2) = e2 else {
        return nil
      }
      let normE1 = self.toWeakHeadNormalForm(t1).ignoreBlocking
      let normE2 = self.toWeakHeadNormalForm(t2).ignoreBlocking
      switch (normE1, normE2) {
      case let (.apply(.variable(v1), _), .apply(.variable(v2), _)):
        return Named<Bool>(v1.name, v1 != v2)
      default:
        return nil
      }
    }
  }
}
