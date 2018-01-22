/// Normalize.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho
import Basic

extension Result: Error {}

// Representation of blocked terms.
enum Blocked {
  enum Head {
    case onFunction(Opened<QualifiedName, TT>)
  }

  // The term is not blocked.
  case notBlocked(TT)
  // The term is headed by some blocking thing.
  case onHead(Meta, [Elim<TT>])
  // Some metavariables are preventing us from reducing a definition.
  case onMetas(Set<Meta>, Head, [Elim<TT>])

  var blockedMetas: Set<Meta>? {
    switch self {
    case .notBlocked(_):
      return nil
    case let .onHead(mv, _):
      return [mv]
    case let .onMetas(mvs, _, _):
      return mvs
    }
  }

  var ignoreBlocking: TT {
    switch self {
    case let .notBlocked(e):
      return e
    case let .onHead(mv, es):
      return .apply(.meta(mv), es)
    case let .onMetas(_, head, es):
      switch head {
      case let .onFunction(f):
        return .apply(.definition(f), es)
      }
    }
  }
}

extension TypeChecker {
  /// Reduces a TT term to head normal form, and produces a representation of
  /// any new problems encountered during the reduction.
  ///
  /// A term is in weak head-normal form when it is
  ///   - An unapplied lambda
  ///   - A constructor either applied or unapplied.
  func toWeakHeadNormalForm(_ t: TT) -> Blocked {
    switch t {
    // If we have a definition, try to complete it by instantiating it.
    case let .apply(.definition(name), es):
      guard let def = self.signature.lookupDefinition(name.key) else {
        return .notBlocked(t)
      }

      guard case let .constant(_, .function(inst)) = def.inside else {
        return .notBlocked(t)
      }

      guard case let .invertible(inv) = inst else {
        return .notBlocked(t)
      }

      let clauses = inv.ignoreInvertibility.map { clause in
        return self.forceInstantiate(clause, name.args)
      }
      print(clauses)
      print(es)
      fatalError()
//      return self.eliminateClauses(clauses, es)

    // If we have an application with an unknown callee, try to
    // eagerly solve for it if possible.
    case let .apply(.meta(mv), es):
      // If we've solved this meta before, grab the binding.
      guard let mvb = self.signature.lookupMetaBinding(mv) else {
        return Blocked.onHead(mv, es)
      }

      // Perform the eliminations up front and reduce the result.
      guard es.count > mvb.arity else {
        let elimVar = self.eliminate(mvb.internalize, es)
        return self.toWeakHeadNormalForm(elimVar)
      }

      let elimVar = self.eliminate(mvb.internalize,
                                   [Elim<TT>](es.prefix(mvb.arity)))
      return self.toWeakHeadNormalForm(elimVar)
    default:
      return .notBlocked(t)
    }
  }

  /// Apply a list of eliminations to a term.
  ///
  /// Performs reduction to WHNF before applying each elimination.
  func eliminate(_ t: TT, _ elims: [Elim<TT>]) -> TT {
    var term = t
    for e in elims {
      switch (self.toWeakHeadNormalForm(term).ignoreBlocking, e) {
      case let (.constructor(_, args), .project(proj)):
        let ix = proj.key.field.unField
        guard ix < args.count else {
          fatalError()
        }
        term = args[ix]
      case let (.lambda(body), .apply(argument)):
        term = self.forceInstantiate(body, [argument])
      case let (.apply(h, es1), _):
        return TT.apply(h, es1 + elims)
      default:
        fatalError()
      }
    }
    return term
  }

  func etaExpand(_ type: Type<TT>, _ term: Term<TT>) -> Term<TT> {
    switch self.toWeakHeadNormalForm(type).ignoreBlocking {
    case let .apply(.definition(tyCon), _):
      let (_, tyConDef) = self.getOpenedDefinition(tyCon.key)
      switch tyConDef {
      case let .constant(_, .record(dataCon, projs)):
        switch self.toWeakHeadNormalForm(term).ignoreBlocking {
        case .constructor(_, _):
          return term
        default:
          return TT.constructor(dataCon, projs.map { p in
            return self.eliminate(term, [ Elim<TT>.project(p) ])
          })
        }
      default:
        return term
      }
    case .pi(_, _):
      let v = TT.apply(Head.variable(Var(wildcardName, 0)), [])
      switch self.toWeakHeadNormalForm(term).ignoreBlocking {
      case .lambda(_):
        return term
      default:
        let tp = term.forceApplySubstitution(.weaken(1), self.eliminate)
        return TT.lambda(self.eliminate(tp, [.apply(v)]))
      }
    default:
      return term
    }
  }

  func etaContract(_ t: Term<TT>) -> Term<TT> {
    switch t {
    case let .lambda(body):
      let normBody = self.toWeakHeadNormalForm(
                        self.etaContract(body)).ignoreBlocking
      guard case let .apply(h, elims) = normBody, !elims.isEmpty else {
        return t
      }
      guard case let .some(.apply(at)) = elims.last else {
        return t
      }
      let normAt = self.toWeakHeadNormalForm(at).ignoreBlocking
      guard case let .apply(.variable(v), es) = normAt, es.isEmpty else {
        return t
      }
      assert(v.index == 0)
      return TT.apply(h, [Elim<TT>](elims.dropLast()))
               .forceApplySubstitution(.strengthen(1), self.eliminate)
    case let .constructor(dataCon, args):
      let (_, openedData) = self.getOpenedDefinition(dataCon.key)
      guard case let .dataConstructor(tyCon, _, _) = openedData else {
        return t
      }
      let (_, openedTyCon) = self.getOpenedDefinition(tyCon.key)
      guard case let .constant(_, .record(_, fields)) = openedTyCon else {
        return t
      }
      assert(args.count == fields.count)
      fatalError()
    default:
      return t
    }
  }
}
