/// IRGenGraphIR.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import LLVM
import Seismography
import OuterCore
import PrettyStackTrace

extension IRGenGIRFunction: PrimOpVisitor {
  func visitFunctionRefOp(_ op: FunctionRefOp) {
    guard let fn = self.blockMap[op.function] else {
      fatalError("Formed ref to undeclared function?")
    }
    guard let fnPtr = fn.bb.parent else {
      fatalError("Function referenced block with undeclared parent?")
    }
    self.loweredValues[op] = .functionPointer(fnPtr)
  }

  func visitThickenOp(_ op: ThickenOp) {
    let from = self.getLoweredExplosion(op.function)
    let to = Explosion()
    to.append(from.claimSingle())
    to.append(IGM.refCountedPtrTy.constPointerNull())
    self.loweredValues[op] = .explosion([IRValue](to.claim()))
  }
}

extension IRGenGIRFunction {
  func visitApplyOp(_ op: ApplyOp) {
    return trace("emitting LLVM IR for apply '\(op)'") {
      switch op.callee {
      case let param as Seismography.Parameter:
        // If we're getting a parameter as the callee of an `apply`, this is
        // a return continuation we're calling.
        //
        // FIXME: This is only correct becausd we don't do closure
        // lowering yet.
        guard param == param.parent.parameters.last else {
          fatalError("call parameter directly without function_ref?")
        }
        assert(op.arguments.count == 1,
               "return continuations must have 1 argument")
        return self.visitApplyAsReturn(op)
      case let funcRef as FunctionRefOp:
        return self.visitApplyAsBranch(op, funcRef)
      default:
        _ = B.buildUnreachable()
        return
      }
    }
  }

  func visitApplyAsBranch(_ op: ApplyOp, _ funcRef: FunctionRefOp) {
    guard let lbb = self.blockMap[funcRef.function] else {
      fatalError("Built function ref to invalid basic block")
    }
    var phiIndex = 0
    for arg in op.arguments {
      if arg.value == self.schedule.scope.entry.parameters.last {
        continue
      }

      if arg.value.type.category == .address {
        let curBB = self.B.insertBlock!
        defer { phiIndex += 1 }
        guard
          case let .some(.address(argValue)) = self.loweredValues[arg.value]
        else {
          fatalError()
        }
        lbb.phis[phiIndex].addIncoming([(argValue.address, curBB)])
        continue
      }

      let argValue = self.getLoweredExplosion(arg.value)
      let curBB = self.B.insertBlock!
      while !argValue.isEmpty {
        defer { phiIndex += 1 }
        lbb.phis[phiIndex].addIncoming([(argValue.claimSingle(), curBB)])
      }
    }
    self.B.buildBr(lbb.bb)
  }

  func visitApplyAsReturn(_ op: ApplyOp) {
    let result = self.getLoweredExplosion(op.arguments.first!.value)
    guard let calleeTy = op.callee.type as? Seismography.FunctionType else {
      fatalError()
    }

    let resultTy = calleeTy.arguments[0]
    let resultTI = self.getTypeInfo(resultTy)

    // Even if GIR has a direct return, the IR-level calling convention may
    // require an indirect return.
    if let indirectRet = self.indirectReturn {
      guard let loadableTI = resultTI as? LoadableTypeInfo else {
        fatalError()
      }
      loadableTI.initialize(self, result, indirectRet)
      self.B.buildRetVoid()
      return
    }

    guard !result.isEmpty else {
      self.B.buildRetVoid()
      return
    }

    let nativeSchema = self.IGM.typeConverter.returnConvention(for: resultTy)
    assert(!nativeSchema.isIndirect)

    guard result.count > 1 else {
      self.B.buildRet(result.claimSingle())
      return
    }
    var resultAgg = nativeSchema.legalizedType(in: IGM.module.context).undef()
    for i in 0..<result.count {
      let elt = result.claimSingle()
      resultAgg = B.buildInsertValue(aggregate: resultAgg,
                                     element: elt, index: i)
    }
    self.B.buildRet(resultAgg)
  }
}

extension IRGenGIRFunction {
  func visitAllocaOp(_ op: AllocaOp) {
    let type = self.getTypeInfo(op.addressType)
    let addr = type.allocateStack(self, op.addressType)
    self.loweredValues[op] = .stackAddress(addr)
  }

  func visitDeallocaOp(_ op: DeallocaOp) {
    let allocatedTy = op.addressValue.type
    let allocatedTI = self.getTypeInfo(allocatedTy)
    let lowVal = self.loweredValues[op.addressValue]
    guard case let .some(.stackAddress(stackAddr)) = lowVal else {
      fatalError("Attempted to lower dealloca with non-alloca operand?")
    }

    allocatedTI.deallocateStack(self, stackAddr, allocatedTy)
  }
}

extension IRGenGIRFunction {
  func visitCopyValueOp(_ op: CopyValueOp) {
    let inExplosion = self.getLoweredExplosion(op.value.value)
    let outExplosion = Explosion()
    let opTy = op.value.value.type
    guard let loadableTI = self.getTypeInfo(opTy) as? LoadableTypeInfo else {
      fatalError()
    }
    loadableTI.copy(self, inExplosion, outExplosion)
    self.loweredValues[op] = .explosion([IRValue](outExplosion.claim()))
  }

  func visitDestroyValueOp(_ op: DestroyValueOp) {
    let inExplosion = self.getLoweredExplosion(op.value.value)
    let opTy = op.value.value.type
    guard let loadableTI = self.getTypeInfo(opTy) as? LoadableTypeInfo else {
      fatalError()
    }
    loadableTI.consume(self, inExplosion)
  }
}

extension IRGenGIRFunction {
  func visitSwitchConstrOp(_ op: SwitchConstrOp) {
    let inExplosion = self.getLoweredExplosion(op.matchedValue)

    var dests = [(String, BasicBlock)]()
    dests.reserveCapacity(op.patterns.count)
    for (pat, apply) in op.patterns {
      guard let funcRef = apply as? FunctionRefOp else {
        fatalError()
      }

      // If the destination BB accepts the case argument, set up a waypoint BB
      // so we can feed the values into the argument's PHI node(s).
      if !funcRef.function.parameters.isEmpty {
        let name = IGM.mangler.mangle(funcRef.function)
        let bb = self.function.appendBasicBlock(named: name + "_waypoint")
        dests.append((pat, bb))
      } else {
        guard let LBB = self.blockMap[funcRef.function] else {
          fatalError()
        }
        dests.append((pat, LBB.bb))
      }
    }
    let defaultDest = op.default.flatMap { defaultOp in
      // swiftlint:disable force_cast
      return self.blockMap[(defaultOp as! FunctionRefOp).function]?.bb
    }

    // Emit the dispatch.
    let eis = self.datatypeStrategy(for: op.matchedValue.type)
    eis.emitSwitch(self, inExplosion, dests, defaultDest)

    // Bind arguments for cases that want them.
    for (i, (pattern: selector, apply: apply)) in op.patterns.enumerated() {
      guard let funcRef = apply as? FunctionRefOp else {
        fatalError()
      }

      guard !funcRef.function.parameters.isEmpty else {
        continue
      }

      let waypointBB = dests[i].1
      let destLBB = self.blockMap[funcRef.function]!

      self.B.positionAtEnd(of: waypointBB)
      let projected = Explosion()
      eis.emitDataProjection(self, selector, inExplosion, projected)

      var index = 0
      let curBB = self.B.insertBlock!
      while !projected.isEmpty {
        defer { index += 1 }
        destLBB.phis[index].addIncoming([(projected.claimSingle(), curBB)])
      }

      self.B.buildBr(destLBB.bb)
    }
  }
}

extension IRGenGIRFunction {
  func visitDataInitOp(_ op: DataInitOp) {
    let data = Explosion()
    if let argTuple = op.argumentTuple {
      let expl = self.getLoweredExplosion(argTuple)
      expl.transfer(into: data, expl.count)
    }
    let out = Explosion()
    self.datatypeStrategy(for: op.dataType)
        .emitDataInjection(self, op.constructor, data, out)
    self.loweredValues[op] = .explosion([IRValue](out.claim()))
  }
}

extension IRGenGIRFunction {
  func visitLoadOp(_ op: LoadOp) {
    let lowered = Explosion()
    guard
      case let .some(.address(source)) = self.loweredValues[op.addressee]
    else {
      fatalError()
    }
    let objType = op.type
    guard let typeInfo = getTypeInfo(objType) as? LoadableTypeInfo else {
      fatalError()
    }

    switch op.ownership {
    case .copy:
      typeInfo.loadAsCopy(self, source, lowered)
    case .take:
      typeInfo.loadAsTake(self, source, lowered)
    }

    self.loweredValues[op] = .explosion([IRValue](lowered.claim()))
  }

  func visitStoreOp(_ op: StoreOp) {
    let source = self.getLoweredExplosion(op.value)
    guard let loweredDest = self.loweredValues[op.address] else {
      fatalError()
    }
    let dest = loweredDest.asAnyAddress()
    let objType = op.value.type

    guard let typeInfo = self.getTypeInfo(objType) as? LoadableTypeInfo else {
      fatalError()
    }
    typeInfo.initialize(self, source, dest)
    self.loweredValues[op] = .explosion([dest.address])
  }
}

extension IRGenGIRFunction {
  func visitAllocBoxOp(_ op: AllocBoxOp) {
    guard
      let boxTy = op.type as? BoxType,
      let boxTI = self.getTypeInfo(boxTy) as? BoxTypeInfo
    else {
      fatalError()
    }
    let boxWithAddr = boxTI.allocate(self, op.boxedType)
    self.loweredValues[op] = .box(boxWithAddr)
  }

  func visitProjectBoxOp(_ op: ProjectBoxOp) {
    guard
      let boxTy = op.boxValue.type as? BoxType,
      let val = self.loweredValues[op.boxValue]
    else {
      fatalError()
    }
    switch val {
    case let .box(addr):
      // The operand is an alloc_box. We can directly reuse the address.
      self.loweredValues[op] = .address(addr.address)
    default:
      // The slow-path: we have to emit code to get from the box to it's
      // value address.
      let box = val.explode(self, op.boxValue.type)
      guard
        let boxOpTy = op.type as? BoxType,
        let boxTI = self.getTypeInfo(boxOpTy) as? BoxTypeInfo
      else {
        fatalError()
      }
      let addr = boxTI.project(self, box.claimSingle(), boxTy)
      self.loweredValues[op] = .address(addr)
    }
  }

  func visitDeallocBoxOp(_ op: DeallocBoxOp) {
    let owner = self.getLoweredExplosion(op.box)

    let ownerPtr = owner.claimSingle()
    guard
      let boxTy = op.box.type as? BoxType,
      let boxTI = self.getTypeInfo(boxTy) as? BoxTypeInfo
    else {
      fatalError()
    }
    boxTI.deallocate(self, ownerPtr, boxTy.underlyingType)
  }
}

extension IRGenGIRFunction {
  func visitCopyAddressOp(_ op: CopyAddressOp) {
    let addrTy = op.value.type
    let addrTI = self.getTypeInfo(addrTy)
    guard case let .some(.address(src)) = self.loweredValues[op.value] else {
      fatalError()
    }
    // See whether we have a deferred fixed-size buffer initialization.
    guard let loweredDest = self.loweredValues[op.address] else {
      fatalError()
    }
    let dest = loweredDest.asAnyAddress()
    addrTI.assignWithCopy(self, dest, src, addrTy)
  }

  func visitDestroyAddressOp(_ op: DestroyAddressOp) {
    let addrTy = op.value.type
    let addrTI = self.getTypeInfo(addrTy)
    guard case let .some(.address(base)) = self.loweredValues[op.value] else {
      fatalError()
    }
    addrTI.destroy(self, base, addrTy)
  }
}

extension IRGenGIRFunction {
  func visitForceEffectsOp(_ op: ForceEffectsOp) {
    // This is effectively a no-op.
    self.loweredValues[op] = self.loweredValues[op.subject]
  }

  func visitUnreachableOp(_ op: UnreachableOp) {
    _ = B.buildUnreachable()
  }
}

extension IRGenGIRFunction {
  func visitTupleOp(_ op: TupleOp) {
    let out = Explosion()
    for elt in op.operands {
      let expl = self.getLoweredExplosion(elt.value)
      expl.transfer(into: out, expl.count)
    }
    self.loweredValues[op] = .explosion([IRValue](out.claim()))
  }

  func visitTupleElementAddress(_ op: TupleElementAddressOp) {
    guard case let .some(.address(base)) = self.loweredValues[op.tuple] else {
      fatalError()
    }

    let baseType = op.tuple.type
    let TI = self.getTypeInfo(baseType)
    guard let tupleTI = TI as? TupleTypeInfo else {
      fatalError()
    }
    let field = tupleTI.projectElementAddress(self, base, baseType, op.index)
    self.loweredValues[op] = .address(field)
  }
}
