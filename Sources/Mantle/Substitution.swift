/// Substitution.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Moho
import Basic

/// A substitution `σ: Δ → Γ` can be seen as a list of terms `Γ ⊢ vᵢ: Aᵢ`
/// with `Aᵢ` from `Δ`, that can be applied to a term `Δ ⊢ uᵢ: Bᵢ` yielding
/// `Γ ⊢ uᵢσ: Bᵢσ` by substituting each `vᵢ` for a variable in `uᵢ`.
public struct Substitution {
  indirect enum Internal {
    /// Identity substitution.
    case id

    /// Weakning substitution lifts to an extended context by the given amount.
    case weaken(Int, Internal)

    /// Strengthening substitution drops to a contracted context by the given
    /// amount.
    case strengthen(Int, Internal)

    /// Extends the substitution with an instantiation.
    case instantiate(TT, Internal)

    /// Lifting substitution lifts the substitution under a given number
    /// of binders.
    case lift(Int, Internal)
  }

  let raw: Internal

  /// Create the identity substitution.
  init() {
    self.raw = .id
  }

  private init(raw: Internal) {
    self.raw = raw
  }

  var isIdentity: Bool {
    switch self.raw {
    case .id: return true
    default: return false
    }
  }

  static func weaken(_ i: Int, _ s: Substitution = .init()) -> Substitution {
    switch (i, s.raw) {
    case (0, _): return s
    case let (n, .weaken(m, rho)):
      return Substitution(raw: .weaken(n + m, rho))
    case let (n, .strengthen(m, rho)):
      let level = n - m
      if level == 0 {
        return s
      } else if level > 0 {
        return Substitution(raw: .weaken(level, rho))
      } else {
        return Substitution(raw: .strengthen(level, rho))
      }
    default:
      return Substitution(raw: .weaken(i, s.raw))
    }
  }

  static func strengthen(
    _ i: Int, _ s: Substitution = .init()) -> Substitution {
    switch (i, s.raw) {
    case (0, _): return s
    case let (n, .strengthen(m, rho)):
      return Substitution(raw: .strengthen(n + m, rho))
    case let (n, .weaken(m, rho)):
      let level = n - m
      if level == 0 {
        return s
      } else if level > 0 {
        return Substitution(raw: .strengthen(level, rho))
      } else {
        return Substitution(raw: .weaken(level, rho))
      }
    default:
      return Substitution(raw: .strengthen(i, s.raw))
    }
  }

  static func instantiate(
    _ tt: TT, _ sub: Substitution = .init()) -> Substitution {
    switch (tt, sub.raw) {
    case let (.apply(.variable(v), es), .weaken(m, sigma)):
      guard es.isEmpty && v.index + 1 == m else {
        return Substitution(raw: .instantiate(tt, sub.raw))
      }
      return self.weaken(m - 1, self.lift(1, Substitution(raw: sigma)))
    default:
      return Substitution(raw: .instantiate(tt, sub.raw))
    }
  }

  static func lift(_ i: Int, _ sub: Substitution) -> Substitution {
    assert(i >= 0, "Cannot lift by a negative amount")

    switch (i, sub.raw) {
    case (0, _): return sub
    case (_, .id): return sub
    case let (m, .lift(n, rho)): return Substitution(raw: .lift(n + m, rho))
    default: return Substitution(raw: .lift(i, sub.raw))
    }
  }

  enum BadStrengthen: Error {
    case name(Name)
  }

  func lookup(
    _ variable: Var, _ elim: (TT, [Elim<TT>]) -> TT
  ) -> Result<Term<TT>, BadStrengthen> {
    func go(
      _ rho: Substitution, _ i: UInt, _ elim: (TT, [Elim<TT>]) -> TT
    ) -> Result<Term<TT>, BadStrengthen> {
      switch rho.raw {
      case .id:
        return .success(TT.apply(.variable(Var(variable.name, i)), []))
      case let .weaken(n, .id):
        let j = i + UInt(n)
        return .success(TT.apply(.variable(Var(variable.name, j)), []))
      case let .weaken(n, rho2):
        let rec = go(Substitution(raw: rho2), i, elim)
        guard case let .success(tm) = rec else {
          return rec
        }
        return .success(tm.applySubstitution(.weaken(n), elim))
      case let .instantiate(u, rho2):
        if i == 0 {
          return .success(u)
        }
        return go(Substitution(raw: rho2), i-1, elim)
      case let .strengthen(n, rho2):
        if i >= UInt(n) {
          return go(Substitution(raw: rho2), i - UInt(n), elim)
        }
        return .failure(BadStrengthen.name(variable.name))
      case let .lift(n, rho2):
        if i < n {
          return .success(TT.apply(.variable(Var(variable.name, i)), []))
        }
        let rec = go(Substitution(raw: rho2), i - UInt(n), elim)
        guard case let .success(tm) = rec else {
          return rec
        }
        return .success(tm.applySubstitution(.weaken(n), elim))
      }
    }
    return go(self, variable.index, elim)
  }
}

public protocol Substitutable {
  func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT) -> Self
}

extension TypeChecker {
  func instantiate<A: Substitutable>(_ t: A, _ ts: [Term<TT>]) -> A {
    return t.applySubstitution(ts.reduce(Substitution(), { acc, next in
      return Substitution.instantiate(next, acc)
    }), self.eliminate)
  }

  // FIXME: Conditional conformances obviate this overload
  func instantiate(_ t: TT, _ ts: [Term<TT>]) -> TT {
    return t.applySubstitution(ts.reduce(Substitution(), { acc, next in
      return Substitution.instantiate(next, acc)
    }), self.eliminate)
  }
}

extension Contextual where T == TT, A: Substitutable {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT
  ) -> Contextual<T, A> {
    return Contextual(telescope: self.telescope.map {
                                   ($0.0, $0.1.applySubstitution(subst, elim))
                                 },
                      inside: self.inside.applySubstitution(
                                            .lift(self.telescope.count, subst),
                                            elim))
  }
}

extension Contextual where T == TT {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT
  ) -> Contextual<T, A> {
    return Contextual(telescope: self.telescope.map {
                                   ($0.0, $0.1.applySubstitution(subst, elim))
                                 },
                      inside: self.inside)
  }
}

extension Opened where T == TT {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT
  ) -> Opened<K, T> {
    return Opened(self.key, self.args.map {$0.applySubstitution(subst, elim)})
  }
}

extension TypeTheory where T == Expr {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT
  ) -> TypeTheory<T> {
    guard !subst.isIdentity else {
      return self
    }

    switch self {
    case .type:
      return .type
    case .refl:
      return .refl
    case let .lambda(body):
      return .lambda(body.applySubstitution(.lift(1, subst), elim))
    case let .pi(domain, codomain):
      let substDomain = domain.applySubstitution(subst, elim)
      let substCodomain = codomain.applySubstitution(.lift(1, subst), elim)
      return .pi(substDomain, substCodomain)
    case let .constructor(dataCon, args):
      let substArgs = args.map { $0.applySubstitution(subst, elim) }
      return .constructor(dataCon, substArgs)
    case let .apply(head, elims):
      let substElims = elims.map { $0.applySubstitution(subst, elim) }
      switch head {
      case let .variable(v):
        guard case let .success(u) = subst.lookup(v, elim) else {
          fatalError()
        }
        return elim(u, substElims)
      case let .definition(d):
        let substDef = d.applySubstitution(subst, elim)
        return .apply(.definition(substDef), substElims)
      case let .meta(mv):
        return .apply(.meta(mv), substElims)
      }
    case let .equal(type, lhs, rhs):
      let substType = type.applySubstitution(subst, elim)
      let substLHS = lhs.applySubstitution(subst, elim)
      let substRHS = rhs.applySubstitution(subst, elim)
      return .equal(substType, substLHS, substRHS)
    }
  }
}

extension Clause: Substitutable {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT) -> Clause {
    return
      Clause(pattern: self.pattern,
             body: self.body.applySubstitution(.lift(self.boundCount, subst),
                                               elim))
  }
}

extension Elim: Substitutable {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT) -> Elim<T> {
    fatalError()
  }
}

extension Elim where T == TT {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT) -> Elim<T> {
    switch self {
    case let .project(p):
      return .project(p)
    case let .apply(t):
      return .apply(t.applySubstitution(subst, elim))
    }
  }
}

extension Instantiability: Substitutable {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT) -> Instantiability {
    switch self {
    case .open:
      return self
    case .invertible(let i):
      return .invertible(i.applySubstitution(subst, elim))
    }
  }
}

extension Instantiability.Invertibility: Substitutable {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT
  ) -> Instantiability.Invertibility {
    switch self {
    case .notInvertible(let cs):
      return .notInvertible(cs.map {$0.applySubstitution(subst, elim)})
    case .invertible(let cs):
      return .invertible(cs.map {$0.applySubstitution(subst, elim)})
    }
  }
}

extension Definition: Substitutable {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT) -> Definition {
    switch self {
    case let .constant(type, constant):
      return .constant(type.applySubstitution(subst, elim),
                       constant.applySubstitution(subst, elim))
    case let .dataConstructor(tyCon, args, dataConType):
      return .dataConstructor(tyCon, args,
                              dataConType.applySubstitution(subst, elim))
    case let .module(mod):
      return .module(Module(telescope: mod.telescope.map {
                                         ($0.0,
                                          $0.1.applySubstitution(subst, elim))
                                       },
                            inside: mod.inside))
    }
  }
}

extension Definition.Constant: Substitutable {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT
  ) -> Definition.Constant {
    switch self {
    case .function(let inst):
      return .function(inst.applySubstitution(subst, elim))
    default:
      return self
    }
  }
}

extension OpenedDefinition: Substitutable {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT) -> OpenedDefinition {
    switch self {
    case let .constant(type, constant):
      return .constant(type.applySubstitution(subst, elim),
                       constant.applySubstitution(subst, elim))
    case let .dataConstructor(tyCon, args, dataConType):
      return .dataConstructor(tyCon, args,
                              dataConType.applySubstitution(subst, elim))
    case let .module(mod):
      return .module(Module(telescope: mod.telescope.map {
                                         ($0.0,
                                          $0.1.applySubstitution(subst, elim))
                                       },
                            inside: mod.inside))
    }
  }
}

extension OpenedDefinition.Constant: Substitutable {
  public func applySubstitution(
    _ subst: Substitution, _ elim: (TT, [Elim<TT>]) -> TT
  ) -> OpenedDefinition.Constant {
    switch self {
    case .function(let i):
      return .function(i.applySubstitution(subst, elim))
    default:
      return self
    }
  }
}
