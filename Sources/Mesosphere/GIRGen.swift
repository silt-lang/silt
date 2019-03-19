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
  let f: Continuation
  let GGM: GIRGenModule
  let B: GIRBuilder
  let astType: Type<TT>
//  let loweredType: GIRType
  let params: [(Name, Type<TT>)]
  let returnTy: Type<TT>
  let telescope: Telescope<TT>
  let tc: TypeChecker<CheckPhaseState>
  var varLocs: [Name: Value] = [:]
  let cleanupStack: CleanupStack = CleanupStack()
  let genericEnvironment: GenericEnvironment
  let epilog: Continuation

  init(_ GGM: GIRGenModule, _ f: Continuation,
       _ ty: Type<TT>, _ tel: Telescope<TT>) {
    self.f = f
    self.GGM = GGM
    self.B = GIRBuilder(module: GGM.M)
    self.telescope = tel
    self.tc = GGM.tc
    self.astType = ty
//    self.loweredType = self.B.module.typeConverter.lowerType(ty).type
    let environment = unrollPiIntoEnvironment(tc, ty)
    self.genericEnvironment = environment.genericEnvironment
    self.params = environment.paramTelescope
    self.returnTy = environment.returnType
    self.epilog = Continuation(name: self.f.name, suffix: "_epilog")
  }

  func emitFunction(_ clauses: [Clause]) {
    let (paramVals, returnCont) = self.buildParameterList()
    self.prepareEpilog(returnCont)
    self.emitPatternMatrix(clauses, paramVals)
    self.emitEpilog(returnCont)
  }

  func emitClosure(_ body: Term<TT>) {
    let (paramVals, returnCont) = self.buildParameterList()
    for val in paramVals {
      let name = Name(name: SyntaxFactory.makeUnderscore())
      self.varLocs[name] = val.value
    }
    self.prepareEpilog(returnCont)
    self.emitFinalColumnBody(self.f, body)
    self.emitEpilog(returnCont)
  }

  func prepareEpilog(_ retCont: Parameter) {
    if let param = self.f.indirectReturnParameter {
      self.epilog.appendParameter(type: param.type)
    } else {
      // swiftlint:disable force_cast
      let retTy = retCont.type as! FunctionType
      self.epilog.appendParameter(type: retTy.arguments[0])
    }
    self.B.module.addContinuation(self.epilog)
  }

  func emitEpilog(_ retCont: Parameter) {
    if self.epilog.predecessors.makeIterator().next() != nil {
      _ = self.B.createApply(self.epilog, retCont, self.epilog.parameters)
    } else {
      self.B.module.removeContinuation(self.epilog)
    }
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

  func getPayloadTypeOfConstructors(
    _ con: Opened<QualifiedName, TT>
  ) -> GIRType {
    return self.B.module.typeConverter.getPayloadTypeOfConstructor(con)
  }

  func getPayloadTypeOfConstructorsIgnoringBoxing(
    _ con: Opened<QualifiedName, TT>
  ) -> [GIRType] {
    switch self.B.module.typeConverter.getPayloadTypeOfConstructor(con) {
    case let ty as TupleType:
      return ty.elements
    case let ty as BoxType:
      // swiftlint:disable force_cast
      return (ty.underlyingType as! TupleType).elements
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

  private func buildParameterList() -> ([ManagedValue], Parameter) {
    var params = [ManagedValue]()
    for t in self.params {
      let (_, paramTy) = t
      let ty = self.getLoweredType(paramTy)
      let p = self.appendManagedParameter(type: ty)
      params.append(p)
    }
    if let arch = self.tryFormArchetype(self.returnTy, self.params.count) {
      self.f.appendIndirectReturnParameter(type: arch)
      let ret = self.f.setReturnParameter(type: arch)
      return (params, ret)
    } else {
      let returnContTy = self.getLoweredType(self.returnTy)
      switch returnContTy.category {
      case .address:
        self.f.appendIndirectReturnParameter(type: returnContTy)
      case .object:
        break
      }
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
  let defaultName = Name(name: SyntaxFactory.makeIdentifier("_"))
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
