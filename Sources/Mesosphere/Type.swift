/// Type.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Mantle
import Moho
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
        return self.lowerContextualDefinition(tc, name.key, def)
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
    _ tc: TypeChecker<CheckPhaseState>,
    _ name: QualifiedName,
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
    _ tc: TypeChecker<CheckPhaseState>,
    _ name: QualifiedName,
    _ c: Definition.Constant
  ) -> GIRType {
    if let ty = self.inProgressLowerings[name] { return ty }
    switch c {
    case .function(_):
      fatalError()
    case .postulate:
      fatalError()
    case let .data(constructors):
    return self.module!.dataType(name: name.string, category: .object ) { dt in
        self.inProgressLowerings[name] = dt
        defer { self.inProgressLowerings[name] = nil }
        for constr in constructors {
          let (_, constrDef) = tc.getOpenedDefinition(constr)
          let ty = tc.getTypeOfOpenedDefinition(constrDef)
          let girType = getLoweredType(tc, ty)
          dt.addConstructor(name: constr.string, type: girType)
        }
      }
    case .record(_, _, _):
      fatalError()
    }
  }
}
