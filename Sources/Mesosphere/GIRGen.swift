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
    self.M = GIRModule(name: root.name.string,
                       parent: nil, tc: TypeConverter(root.tc))
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
      self.emitContextualDefinition(declKey, def)
    }
    return self.M
  }

  func getEmittedFunction(_ ref: DeclRef) -> Continuation? {
    return self.emittedFunctions[ref]
  }
}

extension GIRGenModule {
  func emitContextualDefinition(
    _ name: QualifiedName, _ def: ContextualDefinition
  ) {
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

  func emitContextualConstant(_ name: QualifiedName, _ c: Definition.Constant,
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

  func emitFunction(_ name: QualifiedName, _ inst: Instantiability,
                    _ ty: Type<TT>, _ tel: Telescope<TT>) {
    switch inst {
    case .open:
      return // Nothing to do for opaque functions.
    case let .invertible(body):
      let clauses = body.ignoreInvertibility
      let f = Continuation(name: name)
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
  let genericEnvironment: GenericEnvironment

  init(_ GGM: GIRGenModule, _ f: Continuation,
       _ ty: Type<TT>, _ tel: Telescope<TT>) {
    self.f = f
    self.B = GIRBuilder(module: GGM.M)
    self.telescope = tel
    self.tc = GGM.tc
    let environment = unrollPiIntoEnvironment(tc, ty)
    self.genericEnvironment = environment.genericEnvironment
    self.params = environment.paramTelescope
    self.returnTy = environment.returnType
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

  private func tryFormArchetype(_ ty: Type<TT>, _ idx: Int) -> ArchetypeType? {
    guard case let .apply(.variable(v), elims) = ty, elims.isEmpty else {
      return nil
    }
    let archIdx = UInt(idx) - (v.index + 1)
    let key = GenericEnvironment.Key(depth: 0, index: archIdx)
    return self.genericEnvironment.find(key)
  }

  private func buildParameterList() -> ([ManagedValue], Value) {
    var params = [ManagedValue]()
    for (idx, t) in self.params.enumerated() {
      let (_, paramTy) = t
      if let arch = self.tryFormArchetype(paramTy, idx) {
        let p = self.appendManagedParameter(type: arch)
        params.append(p)
      } else {
        let ty = self.getLoweredType(paramTy)
        let p = self.appendManagedParameter(type: ty)
        params.append(p)
      }
    }
    if let arch = self.tryFormArchetype(self.returnTy, self.params.count) {
      self.f.appendIndirectReturnParameter(type: arch)
      let ret = self.f.setReturnParameter(type: arch)
      return (params, ret)
    } else {
      let returnContTy = self.getLoweredType(self.returnTy)
      let ret = self.f.setReturnParameter(type: returnContTy)
      return (params, ret)
    }
  }

  @discardableResult
  private func appendManagedParameter(type: GIRType) -> ManagedValue {
    let val = self.f.appendParameter(type: type)
    return self.pairValueWithCleanup(val)
  }
}

private struct FunctionEnvironment {
  let paramTelescope: Telescope<Type<TT>>
  let returnType: Type<TT>
  let genericEnvironment: GenericEnvironment
}

private func unrollPiIntoEnvironment(
  _ tc: TypeChecker<CheckPhaseState>,
  _ t: Type<TT>
) -> FunctionEnvironment {
  let defaultName = Name(name: TokenSyntax(.identifier("_")))
  var tel = Telescope<Type<TT>>()
  var ty = t
  var archIdx = 0
  var archetypes = [ArchetypeType]()
  while case let .pi(dm, cd) = tc.toNormalForm(ty) {
    ty = cd
    tel.append((defaultName, dm))
    // FIXME: Lower more complex forms to archetypes.
    if case .type = dm {
      archetypes.append(ArchetypeType(index: archIdx))
      archIdx += 1
      continue
    }
  }
  let signature = GenericSignature(archetypes: archetypes)
  let environment = GenericEnvironment(signature: signature)
  return FunctionEnvironment(paramTelescope: tel,
                             returnType: ty,
                             genericEnvironment: environment)
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
    return cleanupStack.pushCleanup(DestroyAddressCleanup.self, temp)
  }
}
