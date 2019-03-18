/// IRGenFunction.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import LLVM
import Seismography
import OuterCore
import PrettyStackTrace

enum LoweredValue {
  case address(Address)
  case stackAddress(StackAddress)
  case explosion([IRValue])
  case functionPointer(Function)
  case box(OwnedAddress)

  /// Produce an explosion for this lowered value.  Note that many
  /// different storage kinds can be turned into an explosion.
  func explode(_ IGF: IRGenFunction, _ type: GIRType) -> Explosion {
    let e = Explosion()
    switch self {
    case .address(_):
      fatalError("not a value")
    case .stackAddress(_):
      fatalError("not a value")
    case let .explosion(explosion):
      e.append(contentsOf: explosion)
    case let .box(ownedAddr):
      e.append(ownedAddr.owner)
    case let .functionPointer(fptr):
      // Bitcast to an opaque pointer type.
      let fnPtr = IGF.B.buildBitCast(fptr, type: PointerType.toVoid)
      e.append(fnPtr)
    }
    return e
  }

  func asAnyAddress() -> Address {
    switch self {
    case let .address(addr):
      return addr
    case let .stackAddress(stackAddr):
      return stackAddr.address
    case let .box(ownedAddr):
      return ownedAddr.address
    default:
      fatalError("not an address")
    }
  }
}

/// A continuation lowered as the pair of a basic block and a vector of PHI
/// nodes - one for each parameter.
struct LoweredBB {
  let bb: BasicBlock
  let phis: [PhiNode]

  init(_ bb: BasicBlock, _ phis: [PhiNode]) {
    self.bb = bb
    self.phis = phis
  }
}

class IRGenFunction {
  unowned let IGM: IRGenModule
  let function: Function
  let functionType: LLVM.FunctionType
  lazy var GR: IRGenRuntime = IRGenRuntime(irGenFunction: self)
  let B: IRBuilder

  init(_ IGM: IRGenModule, _ function: Function, _ fty: LLVM.FunctionType) {
    self.IGM = IGM
    self.function = function
    self.functionType = fty
    self.B = IRBuilder(module: IGM.module)
    self.GR = IRGenRuntime(irGenFunction: self)
    let entryBB = self.function.appendBasicBlock(named: "entry")
    self.B.positionAtEnd(of: entryBB)
  }

  func getTypeInfo(_ ty: GIRType) -> TypeInfo {
    return self.IGM.getTypeInfo(ty)
  }
}

final class IRGenGIRFunction: IRGenFunction {
  let scope: OuterCore.Scope
  let schedule: Schedule
  var blockMap = [Continuation: LoweredBB]()
  var loweredValues = [Value: LoweredValue]()
  var indirectReturn: Address?

  lazy var trapBlock: BasicBlock = {
    let insertBlock = B.insertBlock!
    let block = function.appendBasicBlock(named: "trap")
    B.positionAtEnd(of: block)
    B.buildUnreachable()
    B.positionAtEnd(of: insertBlock)
    return block
  }()

  init(irGenModule: IRGenModule, scope: OuterCore.Scope) {
    self.schedule = Schedule(scope, .early)
    self.scope = scope
    let (f, fty) = irGenModule.function(for: scope.entry)
    super.init(irGenModule, f, fty)
  }

  private func emitEntryReturnPoint(
    _ entry: Continuation,
    _ params: Explosion,
    _ funcTy: Seismography.FunctionType,
    _ requiresIndirectResult: (GIRType) -> Bool
  ) -> [Seismography.Parameter] {
    let directResultType = funcTy.returnType
    if requiresIndirectResult(directResultType) {
      let retTI = self.IGM.getTypeInfo(directResultType)
      self.indirectReturn = retTI.address(for: params.claimSingle())
    }

    // Fast-path: We're not going out by indirect return.
    guard let indirectRet = entry.indirectReturnParameter else {
      return entry.parameters
    }

    let retTI = self.IGM.getTypeInfo(indirectRet.type)
    let retAddr = retTI.address(for: params.claimSingle())
    self.loweredValues[indirectRet] = .address(retAddr)

    return entry.parameters
  }

  func bindParameter(_ param: Seismography.Parameter,
                     _ allParamValues: Explosion) {
    // Pull out the parameter value and its formal type.
    let paramTI = self.getTypeInfo(param.type)
    switch param.type.category {
    case .address:
      let paramAddr = paramTI.address(for: allParamValues.claimSingle())
      self.loweredValues[param] = .address(paramAddr)
    case .object:
      let paramValues = Explosion()
      // If the explosion must be passed indirectly, load the value from the
      // indirect address.
      guard let loadableTI = paramTI as? LoadableTypeInfo else {
        fatalError()
      }
      let nativeSchema = self.IGM.typeConverter
                             .parameterConvention(for: param.type)
      if nativeSchema.isIndirect {
        let paramAddr = loadableTI.address(for: allParamValues.claimSingle())
        loadableTI.loadAsTake(self, paramAddr, paramValues)
      } else {
        if !nativeSchema.isEmpty {
          allParamValues.transfer(into: paramValues, nativeSchema.count)
        } else {
          assert(paramTI.schema.isEmpty)
        }
      }
      self.loweredValues[param] = .explosion([IRValue](paramValues.claim()))
    }
  }


  func emitBody() {
    trace("emitting LLVM IR declaration for function '\(scope.entry.name)'") {
      guard let entryBlock = schedule.blocks.first else {
        fatalError("Scheduled blocks without an entry?")
      }
      for block in schedule.blocks {
        let name = IGM.mangler.mangle(block.parent)
        let basicBlock = function.appendBasicBlock(named: name)
        let phis = self.emitPHINodesForBBArgs(block.parent, basicBlock)
        self.blockMap[block.parent] = LoweredBB(basicBlock, phis)
      }

      let expl = getPrologueExplosion()
      let entry = self.scope.entry
      // swiftlint:disable force_cast
      let funcTy = entry.type as! Seismography.FunctionType

      // Map the indirect return if present.
      let params = self.emitEntryReturnPoint(entry, expl, funcTy) { retType in
        let schema = self.IGM.typeConverter.returnConvention(for: retType)
        return schema.isIndirect
      }

      // Map remaining parameters to LLVM parameters.
      for param in params.dropLast() {
        self.bindParameter(param, expl)
      }

      self.B.positionAtEnd(of: self.function.entryBlock!)
      let entryLBB = blockMap[entryBlock.parent]!
      let properEntry = self.function.entryBlock!
      self.B.buildBr(entryLBB.bb)

      assert(expl.isEmpty || params.count == 1,
             "didn't claim all parameters!")

      for block in schedule.blocks {
        let bb = self.blockMap[block.parent]!
        B.positionAtEnd(of: bb.bb)
        for primop in block.primops {
          _ = emit(primop)
        }
      }

      for (phi, param) in zip(entryLBB.phis, self.function.parameters) {
        param.replaceAllUses(with: phi)
        phi.addIncoming([ (param, properEntry) ])
      }
    }
  }

  /// Initialize an Explosion with the parameters of the current
  /// function.  All of the objects will be added unmanaged.  This is
  /// really only useful when writing prologue code.
  func getPrologueExplosion() -> Explosion {
    let params = Explosion()
    for param in self.function.parameters {
      params.append(param)
    }
    return params
  }

  private func emitPHINodesForType(
    _ type: GIRType, _ ti: TypeInfo, _ phis: inout [PhiNode]
  ) {
    switch type.category {
    case .address:
      phis.append(self.B.buildPhi(PointerType(pointee: ti.llvmType)))
    case .object:
      for elt in ti.schema.elements {
        if elt.isScalar {
          phis.append(self.B.buildPhi(elt.scalarType))
        } else {
          phis.append(self.B.buildPhi(elt.getAggregateType))
        }
      }
    }
  }

  private func emitPHINodesForBBArgs(
    _ continuation: Continuation, _ bb: BasicBlock
  ) -> [PhiNode] {
    var phis = [PhiNode]()
    self.B.positionAtEnd(of: bb)

    for param in continuation.formalParameters {
      let first = phis.count
      let ti = self.getTypeInfo(param.type)

      self.emitPHINodesForType(param.type, ti, &phis)
      switch param.type.category {
      case .address:
        self.loweredValues[param] = .address(ti.address(for: phis.last!))
      case .object:
        let argValue = Explosion()
        for phi in phis[first..<phis.endIndex] {
          argValue.append(phi)
        }
        self.loweredValues[param] = .explosion([IRValue](argValue.claim()))
      }
    }
    return phis
  }

  func emit(_ continuation: Continuation) {

  }

  func emit(_ primOp: PrimOp) {
    _ = visitPrimOp(primOp)
  }

  func getLoweredExplosion(_ key: Value) -> Explosion {
    return self.loweredValues[key]!.explode(self, key.type)
  }

  func datatypeStrategy(for ty: GIRType) -> DataTypeStrategy {
    let ti = self.getTypeInfo(ty)
    switch ti {
    case let ti as LoadableDataTypeTypeInfo:
      return ti.strategy
    case let ti as FixedDataTypeTypeInfo:
      return ti.strategy
    case let ti as DynamicDataTypeTypeInfo:
      return ti.strategy
    default:
      fatalError()
    }
  }
}

extension IRGenFunction {
  func coerceValue(_ value: IRValue, to toTy: IRType) -> IRValue {
    let fromTy = value.type
    // Use the pointer/pointer and pointer/int casts if we can.
    if let toAsPtr = toTy as? PointerType {
      if fromTy is PointerType {
        return self.B.buildBitCast(value, type: toTy)
      }
      let intPtr = self.B.module.dataLayout.intPointerType()
      if fromTy.asLLVM() == intPtr.asLLVM() {
        return self.B.buildIntToPtr(value, type: toAsPtr)
      }
    } else if fromTy is PointerType {
      let intPtr = self.B.module.dataLayout.intPointerType()
      if toTy.asLLVM() == intPtr.asLLVM() {
        return self.B.buildPtrToInt(value, type: intPtr)
      }
    }

    // Otherwise we need to store, bitcast, and load.
    let DL = self.IGM.module.dataLayout

    let fromSize = DL.sizeOfTypeInBits(fromTy)
    let toSize = DL.sizeOfTypeInBits(toTy)
    let bufferTy = fromSize >= toSize ? fromTy : toTy

    let alignment: Alignment = max(DL.abiAlignment(of: fromTy),
                                   DL.abiAlignment(of: toTy))

    let address = self.B.createAlloca(bufferTy, alignment: alignment)
    let size = Size(UInt64(max(fromSize, toSize)))

    _ = self.B.createLifetimeStart(address, size)
    let orig = self.B.createPointerBitCast(of: address,
                                           to: PointerType(pointee: fromTy))
    self.B.buildStore(value, to: orig.address)
    let coerced = self.B.createPointerBitCast(of: address,
                                              to: PointerType(pointee: toTy))
    let loaded = self.B.buildLoad(coerced.address)
    _ = self.B.createLifetimeEnd(address, size)
    return loaded
  }
}

extension IRGenFunction {
  /// Cast the base to i8*, apply the given inbounds offset (in bytes,
  /// as a size_t), and create an address in the given type.
  func emitByteOffsetGEP(
    _ base: IRValue, _ offset: IRValue, _ type: TypeInfo, _ name: String
  ) -> Address {
    let castBase = self.B.buildBitCast(base, type: PointerType.toVoid)
    let gep = self.B.buildInBoundsGEP(castBase, indices: [ offset ])
    let addr = self.B.buildBitCast(gep,
                                   type: PointerType(pointee: type.llvmType),
                                   name: name)
    return type.address(for: addr)
  }
}

extension IRGenFunction {
  func emitAllocEmptyBoxCall() -> IRValue {
    var call = self.B.buildCall(self.IGM.getAllocEmptyBoxFn(), args: [])
    call.callingConvention = CallingConvention.c
    return call
  }

  func emitAllocBoxCall(_ metadata: IRValue) -> (IRValue, Address) {
    var call = self.B.buildCall(self.IGM.getAllocBoxFn(), args: [metadata])
    call.callingConvention = CallingConvention.c
    let box = self.B.buildExtractValue(call, index: 0)
    let addr = Address(self.B.buildExtractValue(call, index: 1),
                       self.IGM.getPointerAlignment())
    return (box, addr)
  }

  func emitDeallocBoxCall(_ box: IRValue, _ metadata: IRValue) {
    var call = self.B.buildCall(self.IGM.getDeallocBoxFn(), args: [box])
    call.callingConvention = CallingConvention.c
  }

  func emitProjectBoxCall(_ box: IRValue, _ metadata: IRValue) -> IRValue {
    var call = self.B.buildCall(self.IGM.getProjectBoxFn(), args: [box])
    call.callingConvention = CallingConvention.c
    return call
  }
}

extension IRGenModule {
  func getAllocEmptyBoxFn() -> Function {
    guard let fn = self.module.function(named: "silt_allocEmptyBox") else {
      let fnTy = FunctionType(argTypes: [], returnType: self.refCountedPtrTy)
      return self.B.addFunction("silt_allocEmptyBox", type: fnTy)
    }
    return fn
  }

  func getAllocBoxFn() -> Function {
    guard let fn = self.module.function(named: "silt_allocBox") else {
      let retTy = StructType(elementTypes: [
        self.refCountedPtrTy, // Addr
        self.opaquePtrTy,     // Metadata
      ])
      let fnTy = FunctionType(argTypes: [ self.typeMetadataPtrTy ],
                              returnType: retTy)
      return self.B.addFunction("silt_allocBox", type: fnTy)
    }
    return fn
  }

  func getDeallocBoxFn() -> Function {
    guard let fn = self.module.function(named: "silt_deallocBox") else {
      let fnTy = FunctionType(argTypes: [ self.refCountedPtrTy ],
                              returnType: VoidType())
      return self.B.addFunction("silt_deallocBox", type: fnTy)
    }
    return fn
  }

  func getProjectBoxFn() -> Function {
    guard let fn = self.module.function(named: "silt_deallocBox") else {
      let fnTy = FunctionType(argTypes: [ self.refCountedPtrTy ],
                              returnType: self.refCountedPtrTy)
      return self.B.addFunction("silt_deallocBox", type: fnTy)
    }
    return fn
  }
}
