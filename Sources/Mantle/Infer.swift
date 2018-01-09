/// Infer.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho

extension TypeChecker where PhaseState == CheckPhaseState {
  // Type inference for Type Theory terms.
  //
  // Inference is easy since we've already scope checked terms: just look into
  // the context.
  func infer(_ t: Term<TT>, in ctx: Context) -> Type<TT> {
    switch t {
    case .type:
      return .type
    case let .pi(domain, codomain):
      self.checkTT(domain, hasType: TT.type, in: ctx)
      let name = TokenSyntax(.identifier("_")) // FIXME: Try harder, maybe
      self.checkTT(codomain, hasType: TT.type, in: [(Name(name: name), domain)])
      return TT.type
    case let .apply(head, elims):
      var type = self.infer(head, in: ctx)
      var head = TT.apply(head, [])
      for el in elims {
        switch el {
        case let .apply(arg):
          guard case let .pi(dom, cod) = type else {
            fatalError()
          }
          self.checkTT(arg, hasType: dom, in: ctx)
          type = self.forceInstantiate(cod, [arg])
          head = self.eliminate(head, [.apply(arg)])
        case let .project(proj):
          print(proj)
          fatalError()
        }
      }
      return type
    case let .equal(type, lhs, rhs):
      self.checkTT(type, hasType: TT.type, in: ctx)
      self.checkTT(lhs, hasType: type, in: ctx)
      self.checkTT(rhs, hasType: type, in: ctx)
      return TT.type
    default:
      fatalError()
    }
  }
}

extension TypeChecker where PhaseState == CheckPhaseState {
  func inferInvertibility(_ cs: [Clause]) -> Instantiability.Invertibility {
    var seenHeads = Set<Instantiability.Invertibility.TermHead>()
    seenHeads.reserveCapacity(cs.count)
    var injectiveClauses = [Clause]()
    injectiveClauses.reserveCapacity(cs.count)
    for clause in cs {
      switch clause.body {
      case let .apply(.definition(name), _):
        switch self.getOpenedDefinition(name.key).1 {
        case .constant(_, .data(_)),
             .constant(_, .record(_, _)),
             .constant(_, .postulate):
          guard seenHeads.insert(.definition(name.key)).inserted else {
            return .notInvertible(cs)
          }
          injectiveClauses.append(clause)
        case .constant(_, .function(_)),
             .dataConstructor(_, _, _):
          return .notInvertible(cs)
        case .module(_):
          fatalError()
        }
      case .apply(_, _):
        return .notInvertible(cs)
      case let .constructor(name, _):
        guard seenHeads.insert(.definition(name.key)).inserted else {
          return .notInvertible(cs)
        }
        injectiveClauses.append(clause)
      case .pi(_, _):
        guard seenHeads.insert(.pi).inserted else {
          return .notInvertible(cs)
        }
        injectiveClauses.append(clause)
      case .lambda(_),
           .refl,
           .type,
           .equal(_, _, _):
        return .notInvertible(cs)
      }
    }
    return .invertible(injectiveClauses)
  }
}

extension TypeChecker {
  func infer(_ h: Head<TT>, in ctx: Context) -> Type<TT> {
    switch h {
    case let .variable(v):
      return Environment(ctx).lookupVariable(v, self.eliminate)!
    case let .definition(name):
      let contextDef = self.signature.lookupDefinition(name.key)!
      let openedDef = self.openContextualDefinition(contextDef, name.args)
      return self.getTypeOfOpenedDefinition(openedDef)
    case let .meta(mv):
      return self.signature.lookupMetaType(mv)!
    }
  }
}
