/// Invert.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho
import Basic

extension TypeChecker {
  /// An inversion is a substitution mapping the free variables in the spine of
  /// an applied metavariable to TT terms.
  ///
  /// An inversion may fail to create a non-trivial substitution map.  Thus,
  /// we also tag the inversion with the arity of the type so we don't lie
  /// to the signature while solving.
  struct Inversion: CustomStringConvertible {
    let substitution: [(Var, Term<TT>)]
    let arity: Int

    var description: String {
      let invBody = self.substitution.map({ (variable, term) in
        return "\(variable) |-> \(term)"
      }).joined(separator: ", ")
      return "Inversion[\(invBody)]"
    }
  }

  /// Attempts to generate an inversion from a sequence of eliminators.
  ///
  /// Given a metavariable `($0: T)` with spine `[e1, e2, ..., en]` and a
  /// target term `t`, inversion attempts to find a value for `$0` that solves
  /// the equation `$0[e1, e2, ..., en] ≡ t`.
  func invert(_ elims: [Elim<Term<TT>>]) -> Inversion? {
    guard let args = elims.mapM({ $0.applyTerm }) else {
      return nil
    }
    guard let mvArgs = args.mapM(self.checkSpineArgument) else {
      return nil
    }
    return self.tryGenerateInversion(mvArgs)
  }

  /// Checks that the pattern condition holds before generating an inversion.
  ///
  /// The list of variables must be linear.
  func tryGenerateInversion(_ vars: [Var]) -> Inversion? {
    guard vars.count == Set(vars).count else {
      return nil
    }
    guard !vars.isEmpty else {
      return Inversion(substitution: [], arity: vars.count)
    }
    let zips = zip((0..<vars.count).reversed(), vars)
    let subs = zips.map({ (idx, v) -> (Var, Term<TT>) in
      let name = TokenSyntax(.identifier("_")) // FIXME: Try harder, maybe
      return (v, TT.apply(.variable(Var(Name(name: name), UInt(idx))), []))
    })
    return Inversion(substitution: subs, arity: subs.count)
  }

  func checkSpineArgument(_ arg: Term<TT>) -> Var? {
    switch self.toWeakHeadNormalForm(arg) {
    case let .notBlocked(t):
      switch self.toWeakHeadNormalForm(self.etaContract(t)).ignoreBlocking {
      case let .apply(.variable(v), vArgs):
        guard vArgs.mapM({ $0.projectTerm }) != nil else {
          return nil
        }
        return v
      case let .constructor(dataCon, dataArgs):
        print(dataCon, dataArgs)
        fatalError("Support inversion of constructor spines")
      default:
        return nil
      }
    case .onHead(_, _), .onMetas(_, _, _):
      return nil
    }
  }
}

extension TypeChecker where PhaseState == SolvePhaseState {
  typealias InversionResult<T> = Validation<Collect<Var, Set<Meta>>, T>

  // Takes a meta inversion and applies it to a term. If substitution encounters
  // a free variable, this function will fail and return that variable.  If
  // inversion fails because of unsolved metas, the substitution will
  // also fail and return the set of blocking metas.
  func applyInversion(
    _ inversion: Inversion, to term: Term<TT>, in ctx: Context
  ) -> InversionResult<Meta.Binding> {
    func isIdentity(_ ts: [(Var, Term<TT>)]) -> Bool {
      for (v, u) in ts {
        switch self.toWeakHeadNormalForm(u).ignoreBlocking {
        case let .apply(.variable(v2), xs) where xs.isEmpty:
          if v == v2 {
            continue
          }
          return false
        default:
          return false
        }
      }
      return true
    }

    guard isIdentity(inversion.substitution) else {
      return self.applyInversionSubstitution(inversion.substitution, term).map {
        return Meta.Binding(arity: inversion.arity, body: $0)
      }
    }

    // Optimization: The identity substitution requires no work.
    guard ctx.count != inversion.substitution.count else {
      return .success(Meta.Binding(arity: inversion.arity, body: term))
    }

    let fvs = self.freeVars(term)
    let invVars = inversion.substitution.map { $0.0 }
    guard fvs.flexible.union(fvs.rigid).isSubset(of: invVars) else {
      return self.applyInversionSubstitution(inversion.substitution, term).map {
        return Meta.Binding(arity: inversion.arity, body: $0)
      }
    }
    return .success(Meta.Binding(arity: inversion.arity, body: term))
  }

  private func applyInversionSubstitution(
    _ subst: [(Var, Term<TT>)], _ term: Term<TT>
  ) -> InversionResult<Term<TT>> {
    func invert(_ str: UInt, _ v0: Var) -> Either<Var, Term<TT>> {
      guard let v = v0.strengthen(0, by: str) else {
        return .right(TT.apply(.variable(v0), []))
      }

      guard let (_, substVar) = subst.first(where: { $0.0 == v }) else {
        return .left(v)
      }
      return .right(substVar.applySubstitution(.weaken(Int(str)),
                                               self.eliminate))
    }

    func applyInversion(
      after idx: UInt, _ t: Term<TT>
    ) -> Validation<Collect<Var, Set<Meta>>, Term<TT>> {
      switch self.toWeakHeadNormalForm(t).ignoreBlocking {
      case .refl:
        return .success(.refl)
      case .type:
        return .success(.type)
      case let .lambda(body):
        switch applyInversion(after: idx + 1, body) {
        case let .failure(f):
          return .failure(f)
        case let .success(bdy):
          return .success(TT.lambda(bdy))
        }
      case let .pi(domain, codomain):
        let invDomain = applyInversion(after: idx, domain)
        let invCodomain = applyInversion(after: idx + 1, codomain)
        switch invDomain.merge2(invCodomain) {
        case let .success((dom, cod)):
          return .success(TT.pi(dom, cod))
        case let .failure(e):
          return .failure(e)
        }
      case let .equal(type, lhs, rhs):
        let invType = applyInversion(after: idx, type)
        let invLHS = applyInversion(after: idx, lhs)
        let invRHS = applyInversion(after: idx, rhs)
        switch invType.merge2(invLHS).merge2(invRHS) {
        case let .success(((type2, x2), y2)):
          return .success(TT.equal(type2, x2, y2))
        case let .failure(e):
          return .failure(e)
        }
      case let .constructor(dataCon, args):
        switch args.mapM({ arg in applyInversion(after: idx, arg) }) {
        case let .success(args2):
          return .success(TT.constructor(dataCon, args2))
        case let .failure(e):
          return .failure(e)
        }
      case let .apply(h, elims):
        let invElims = elims.mapM({ (e) -> InversionResult<Elim<TT>>  in
          switch e {
          case let .apply(t2):
            return applyInversion(after: idx, t2).map(Elim<TT>.apply)
          case .project(_):
            return .success(e)
          }
        })
        switch h {
        case let .meta(mv):
          switch invElims {
          case let .failure(.collect(mvs)):
            return .failure(.collect(mvs.union([mv])))
          case .failure(.fail(_)):
            return .failure(.collect(Set([mv])))
          default:
            return invElims.map { TT.apply(h, $0) }
          }
        case .definition(_):
          return invElims.map { TT.apply(h, $0) }
        case let .variable(v):
          switch invert(idx, v) {
          case let .right(inv):
            return invElims.map { self.eliminate(inv, $0) }
          case let .left(e):
            return .failure(.fail(e))
          }
        }
      }
    }
    return applyInversion(after: 0, term)
  }
}
