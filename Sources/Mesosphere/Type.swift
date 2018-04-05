/// Type.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Mantle
import Seismography

extension TypeConverter {
  func getLoweredType(
    _ tc: TypeChecker<CheckPhaseState>, _ type: Type<TT>
  ) -> GIRType {
    switch type {
    case let .apply(head, elims) where elims.isEmpty:
      switch head {
      case let .meta(mv):
        guard let bind = tc.signature.lookupMetaBinding(mv) else {
          fatalError()
        }
        return self.getLoweredType(tc, bind.body)
      case let .definition(name):
        guard let def = tc.signature.lookupDefinition(name.key) else {
          fatalError()
        }
        return self.lowerContextualDefinition(tc, name.key.string, def)
      case .variable(_):
        fatalError()
      }
      fatalError()
    case let .pi(dom, cod):
      let loweredDom = self.getLoweredType(tc, dom)
      let loweredCod = self.getLoweredType(tc, cod)
      return module!.functionType(arguments: [loweredDom],
                                  returnType: loweredCod)
    default:
      fatalError()
    }
    fatalError()
  }

  private func lowerContextualDefinition(
    _ tc: TypeChecker<CheckPhaseState>, _ name: String,
    _ def: ContextualDefinition
  ) -> GIRType {
    precondition(def.telescope.isEmpty, "Cannot gen generics yet")

    switch def.inside {
    case .module(_):
      fatalError()
    case let .constant(_, constant):
      return self.lowerContextualConstant(tc, name, constant)
    case .dataConstructor(_, _, _):
      fatalError()
    case .projection(_, _, _):
      fatalError()
    }
  }

  private func lowerContextualConstant(
    _ tc: TypeChecker<CheckPhaseState>, _ name: String,
    _ c: Definition.Constant
  ) -> GIRType {
    switch c {
    case .function(_):
      fatalError()
    case .postulate:
      fatalError()
    case .data(_):
      return self.module!.dataType(name: name, category: .object)
    case .record(_, _, _):
      fatalError()
    }
  }
}
