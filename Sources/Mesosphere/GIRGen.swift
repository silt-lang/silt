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
    self.M = GIRModule(name: root.name.string, tc: TypeConverter(root.tc))
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
  let cleanupStack: CleanupStack = CleanupStack()

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

  public func lowerType(_ type: Type<TT>) -> TypeConverter.Lowering {
    return self.B.module.typeConverter.lowerType(type)
  }

  public func lowerType(_ type: GIRType) -> TypeConverter.Lowering {
    return self.B.module.typeConverter.lowerType(type)
  }

  func getLoweredType(_ type: Type<TT>) -> GIRType {
    return self.B.module.typeConverter.lowerType(type).type
  }

  func getPayloadTypeOfConstructor(
    _ con: Opened<QualifiedName, TT>
  ) -> [GIRType] {
    switch self.B.module.typeConverter.getPayloadTypeOfConstructor(con) {
    case let ty as TupleType:
      return ty.elements
    default:
      fatalError()
    }
  }

  private func buildParameterList() -> ([ManagedValue], Value) {
    var params = [ManagedValue]()
    for (_, paramTy) in self.params {
      let ty = self.getLoweredType(self.tc.toNormalForm(paramTy))
      let p = self.appendManagedParameter(type: ty)
      params.append(p)
    }
    let returnContTy = self.getLoweredType(self.tc.toNormalForm(self.returnTy))
    let ret = self.f.setReturnParameter(type: returnContTy)
    return (params, ret)
  }

  @discardableResult
  private func appendManagedParameter(
    named name: String = "", type: GIRType
  ) -> ManagedValue {
    let val = self.f.appendParameter(named: name, type: type)
    return self.pairValueWithCleanup(val)
  }
}

extension GIRGenFunction {
  func pairValueWithCleanup(_ value: Value) -> ManagedValue {
    let lowering = self.lowerType(value.type)
    if lowering.trivial {
      // Morally true.
      return ManagedValue.unmanaged(value)
    }

    switch value.type.category {
    case .object:
      return ManagedValue(value: value, cleanup: self.cleanupValue(value))
    case .address:
      return ManagedValue(value: value, cleanup: self.cleanupAddress(value))
    }
  }

  func cleanupValue(_ temp: Value) -> CleanupStack.Handle {
    assert(temp.type.category == .object,
           "value cleanup only applies to value types")
    return cleanupStack.pushCleanup(DestroyValueCleanup.self, temp)
  }

  func cleanupAlloca(_ temp: Value) -> CleanupStack.Handle {
    assert(temp.type.category == .address,
           "alloca cleanup only applies to address types")
    return cleanupStack.pushCleanup(DeallocaCleanup.self, temp)
  }

  func cleanupAddress(_ temp: Value) -> CleanupStack.Handle {
    assert(temp.type.category == .address,
           "alloca cleanup only applies to address types")
    return cleanupStack.pushCleanup(DeallocaCleanup.self, temp)
  }
}
