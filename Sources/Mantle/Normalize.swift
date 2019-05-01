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
  /// Evaluates a TT term.
  ///
  /// This strategy is the most drastic form of evaluation and also the most
  /// expensive.  In most cases WHNF suffices.
  public func toNormalForm(_ t: TT) -> TT {
    let normTerm = self.toWeakHeadNormalForm(t).ignoreBlocking
    switch normTerm {
    case .refl:
      return .refl
    case .type:
      return .type
    case let .lambda(body):
      return .lambda(self.toNormalForm(body))
    case let .pi(dom, cod):
      return .pi(self.toNormalForm(dom), self.toNormalForm(cod))
    case let .equal(A, x, y):
      return .equal(self.toNormalForm(A),
                    self.toNormalForm(x), self.toNormalForm(y))
    case let .constructor(dataCon, args):
      return .constructor(dataCon.mapArgs(self.toNormalForm),
                          args.map(self.toNormalForm))
    case let .apply(h, args):
      let newArgs = args.map({ (a) -> Elim<TT> in
        switch a {
        case let .apply(tt):
          return .apply(self.toNormalForm(tt))
        case .project(_):
          return a
        }
      })
      switch h {
      case .meta(_):
        return TT.apply(h, newArgs)
      case .variable(_):
        return TT.apply(h, newArgs)
      case let .definition(def):
        return TT.apply(.definition(def.mapArgs(self.toNormalForm)), newArgs)
      }
    }
  }

  /// Reduces a TT term to weak head normal form.
  ///
  /// This function ignores any problems encountered during the reduction.
  public func forceWHNF(_ t: TT) -> TT {
    return self.toWeakHeadNormalForm(t).ignoreBlocking
  }

  /// Reduces a TT term to weak head normal form, and produces a representation
  /// of any new problems encountered during the reduction.
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
      return self.eliminateClauses(name, clauses, es)

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

  private func exprAsPattern(_ e: Term<TT>) -> [Pattern]? {
    var expr = e
    while true {
      let normE = self.toWeakHeadNormalForm(expr).ignoreBlocking
      switch normE {
      case let .pi(_, codomain):
        expr = codomain
        continue
      case .apply(.meta(_), _):
        return nil
      case let .apply(.definition(_), es):
        return self.elimsAsPatterns(es)
      case let .apply(.variable(_), es) where es.isEmpty:
        fatalError(expr.description)
      default:
        fatalError(expr.description)
      }
    }
  }

  func elimsAsPatterns(_ es: [Elim<TT>]) -> [Pattern]? {
    var pats = [Pattern]()
    for elim in es {
      switch elim {
      case .project(_):
        return nil
      case let .apply(term):
        switch term {
        case let .apply(.variable(v), es) where es.isEmpty:
          pats.append(.variable(v))
        default:
          print(term.description)
        }
      }
    }
    return pats
  }

  func disambiguateConstructor(
    _ set: [QualifiedName], _ ty: Type<TT>) -> QualifiedName? {
    precondition(!set.isEmpty)
    guard set.count > 1 else {
      return set[0]
    }
    switch ty {
    case let .apply(.definition(name), _):
      return QualifiedName(cons: set[0].name, name.key)
    default:
      return nil
    }
  }

  func matchingConstructors(
    _ name: Opened<QualifiedName, TT>, _ cs: [QualifiedName], _ es: [Elim<TT>]
  ) -> [Pattern] {
    guard !cs.isEmpty else {
      return []
    }

    var result = [Pattern]()
    for cname in cs {
      let (constrName, openTypeDef) = self.getOpenedDefinition(cname)
      guard case let .dataConstructor(_, _, ty) = openTypeDef else {
        fatalError()
      }
      guard let pats = self.exprAsPattern(ty.inside) else {
        continue
      }
      switch self.matchClause(es, pats) {
      case .success((_, _)):
        result.append(.constructor(constrName, pats))
        continue
      case .failure(_):
        // FIXME: Check recursive inhabitants as well.
        continue
      }
    }

    return result
  }

  private func eliminateClauses(
    _ name: Opened<QualifiedName, TT>, _ cs: [Clause], _ es: [Elim<TT>]
  ) -> Blocked {
    guard !cs.isEmpty else {
      return .notBlocked(TT.apply(.definition(name), es))
    }

    for clause in cs {
      guard let clauseBody = clause.body else { continue }

      switch self.matchClause(es, clause.patterns) {
      case let .success((args, remainingElims)):
        let instBody = self.forceInstantiate(clauseBody, args)
        return self.toWeakHeadNormalForm(self.eliminate(instBody,
                                                        remainingElims))
      case let .failure(.collect(mvs)):
        return Blocked.onMetas(mvs, .onFunction(name), es)
      case .failure(.fail(_)):
        continue
      }
    }
    return .notBlocked(TT.apply(.definition(name), es))
  }

  typealias ClauseMatch = Validation<Collect<(), Set<Meta>>, ([TT], [Elim<TT>])>
  /// Tries a verbatim match of the eliminations to the pattern list.
  ///
  /// - Fails immediately if the eliminations are incompatible with the clause
  ///   patterns
  /// - Fails with metas if we became blocked while evaluating this pattern.
  /// - Succeeds with the arguments to apply and the remaining unapplied elims.
  private func matchClause(_ es: [Elim<TT>], _ ps: [Pattern]) -> ClauseMatch {
    var result = ClauseMatch.success(([], es))
    guard !ps.isEmpty else {
      return result
    }
    guard es.count >= ps.count else {
      return ClauseMatch.failure(.fail(()))
    }
    var idx = 0
    var arguments = [TT]()
    arguments.reserveCapacity(ps.count)
    for (elim, pattern) in zip(es, ps) {
      defer { idx += 1 }
      switch (elim, pattern) {
      case let (.apply(arg), .variable(_)):
        arguments.append(arg)
        continue
      case let (.apply(arg), .constructor(con1, conPatterns)):
        switch self.toWeakHeadNormalForm(arg) {
        case let .onHead(bl, _):
          result = result.merge(.failure(.collect([bl])))
          continue
        case let .onMetas(mvs, _, _):
          result = result.merge(.failure(.collect(mvs)))
          continue
        case let .notBlocked(t):
          switch t {
          case let .constructor(con2, conArgs) where con1.key == con2.key:
            let mergeEs = conArgs.map({Elim<TT>.apply($0)}) + es
            let mergePats = conPatterns + ps.dropFirst(idx)
            result = result.merge(self.matchClause(mergeEs, mergePats))
            continue
          default:
            return .failure(.fail(()))
          }
        }
      default:
        return .failure(.fail(()))
      }
    }
    guard case .success(_) = result else {
      return result
    }
    return .success((arguments, es))
  }

  /// Apply a list of eliminations to a term.
  ///
  /// Performs reduction to WHNF before applying each elimination.
  public func eliminate(_ t: TT, _ elims: [Elim<TT>]) -> TT {
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
