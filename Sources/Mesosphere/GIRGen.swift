/// GIRGen.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho
import Mantle
import Seismography

public final class GIRGenModule {
  fileprivate var M: GIRModule
  let module: Module
  let environment: Environment
  let signature: Signature
  let tc: TypeChecker<CheckPhaseState>

  struct DelayedContinuation {
    let force: () -> Continuation
  }

  var emittedFunctions: [DeclRef: Continuation] = [:]

  typealias DelayedEmitter = (Continuation) -> Void

  var delayedFunctions: [DeclRef: DelayedEmitter] = [:]

  public init(_ root: TopLevelModule) {
    self.module = root.rootModule
    self.M = GIRModule(name: root.name.string)
    self.environment = root.environment
    self.signature = root.signature
    self.tc = root.tc
  }

  public func emitTopLevelModule() -> GIRModule {
    var visitedDecls = Set<QualifiedName>()
    for declKey in self.module.inside {
      guard visitedDecls.insert(declKey).inserted else { continue }

      guard let def = self.signature.lookupDefinition(declKey) else {
        fatalError()
      }
      self.emitContextualDefinition(declKey.string, def)
    }
    return self.M
  }

  func getEmittedFunction(_ ref: DeclRef) -> Continuation? {
    return self.emittedFunctions[ref]
  }
}

extension GIRGenModule {
  func emitContextualDefinition(_ name: String, _ def: ContextualDefinition) {
    precondition(def.telescope.isEmpty, "Cannot gen generics yet")

    switch def.inside {
    case .module(_):
      fatalError()
    case let .constant(ty, constant):
      self.emitContextualConstant(name, constant, ty, def.telescope)
    case .dataConstructor(_, _, _):
      fatalError()
    case .projection(_, _, _):
      fatalError()
    }
  }

  func emitContextualConstant(_ name: String, _ c: Definition.Constant,
                              _ ty: Type<TT>, _ tel: Telescope<TT>) {
    switch c {
    case let .function(inst):
      self.emitFunction(name, inst, ty, tel)
    case .postulate:
      fatalError()
    case .data(_):
      break
    case .record(_, _, _):
      fatalError()
    }
  }

  func emitFunction(_ name: String, _ inst: Instantiability,
                    _ ty: Type<TT>, _ tel: Telescope<TT>) {
    switch inst {
    case .open:
      return // Nothing to do for opaque functions.
    case let .invertible(body):
      let clauses = body.ignoreInvertibility
      let constant = DeclRef(name, .function)
      let f = Continuation(name: constant.name)
      self.M.addContinuation(f)
      GIRGenFunction(self, f, ty, tel).emitFunction(clauses)
    }
  }

  func emitFunctionBody(
    _ constant: DeclRef, _ emitter: @escaping DelayedEmitter
  ) {
    guard let f = self.getEmittedFunction(constant) else {
      self.delayedFunctions[constant] = emitter
      return
    }
    return emitter(f)
  }
}

final class GIRGenFunction {
  var f: Continuation
  let B: GIRBuilder
  let params: [(Name, Type<TT>)]
  let returnTy: Type<TT>
  let telescope: Telescope<TT>
  let tc: TypeChecker<CheckPhaseState>
  var varLocs: [Name: Value] = [:]

  init(_ GGM: GIRGenModule, _ f: Continuation,
       _ ty: Type<TT>, _ tel: Telescope<TT>) {
    self.f = f
    self.B = GIRBuilder(module: GGM.M)
    self.telescope = tel
    let (ps, result) = GGM.tc.unrollPi(ty)
    self.params = ps
    self.returnTy = result
    self.tc = GGM.tc
  }

  func emitFunction(_ clauses: [Clause]) {
    let (paramVals, returnCont) = self.buildParameterList()
    self.emitPatternMatrix(clauses, paramVals, returnCont)
  }

  func getLoweredType(_ type: Type<TT>) -> GIRType {
    return self.B.module.typeConverter.getLoweredType(self.tc, type)
  }

  private func buildParameterList() -> ([Value], Value) {
    var params = [Value]()
    for (_, paramTy) in self.params {
      let ty = self.getLoweredType(self.tc.toNormalForm(paramTy))
      let p = self.f.appendParameter(type: ty, ownership: .owned)
      params.append(p)
    }
    let returnContTy = self.getLoweredType(self.tc.toNormalForm(self.returnTy))
    let ret = self.f.setReturnParameter(type: returnContTy)
    return (params, ret)
  }
}
