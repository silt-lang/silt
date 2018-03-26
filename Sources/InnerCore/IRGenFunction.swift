import LLVM
import Seismography
import OuterCore
import PrettyStackTrace

final class IRGenFunction: PrimOpVisitor {
  unowned let IGM: IRGenModule
  let scope: Scope
  let schedule: Schedule
  var function: Function?
  var blockMap = [Continuation: BasicBlock]()
  var primOpMap = [PrimOp: IRValue]()

  var B: IRBuilder {
    return IGM.B
  }

  init(irGenModule: IRGenModule, scope: Scope) {
    self.IGM = irGenModule
    self.schedule = Schedule(scope, .early)
    self.scope = scope
  }

  func emitDeclaration() {
    trace("emitting LLVM IR declaration for function '\(scope.entry.name)'") {
      let name = IGM.mangler.mangle(scope.entry)
      let bottom = PointerType.toVoid
      let type = FunctionType(argTypes:
        scope.entry.parameters
             .dropLast().map { _ in bottom}, returnType: bottom)
      self.function = B.addFunction(name, type: type)
    }
  }

  func emitBody() {
    trace("emitting LLVM IR declaration for function '\(scope.entry.name)'") {
      for block in schedule.blocks {
        let name = IGM.mangler.mangle(block.parent)
        let basicBlock = function!.appendBasicBlock(named: name)
        blockMap[block.parent] = basicBlock
      }
      for block in schedule.blocks {
        let bb = blockMap[block.parent]!
        B.positionAtEnd(of: bb)
        for primop in block.primops {
          _ = emit(primop)
        }
      }
    }
  }

  func emit(_ continuation: Continuation) {

  }

  func emit(_ primOp: PrimOp) -> IRValue {
    if let v = primOpMap[primOp] { return v }
    let value = visitPrimOp(primOp)
    primOpMap[primOp] = value
    return value
  }

  func emit(_ value: Value) -> IRValue {
    switch value {
    case let param as Seismography.Parameter:
      return function!.parameter(at: param.index)!
    case let op as PrimOp:
      return emit(op)
    default:
      return B.buildUnreachable()
    }
  }

  func visitApplyOp(_ op: ApplyOp) -> IRValue {
    return trace("emitting LLVM IR for apply '\(op)'") {
      switch op.callee {
      case let param as Seismography.Parameter:
        // If we're getting a parameter as the callee of an `apply`, this is
        // a return continuation we're calling. If that's the case,
        guard param == param.parent.parameters.last else {
          fatalError("call parameter directly without function_ref?")
        }
        assert(op.arguments.count == 1,
               "return continuations must have 1 argument")
        return B.buildRet(emit(op.arguments.first!.value))
      case let funcRef as FunctionRefOp:
        let bb = emit(funcRef) as! BasicBlock
        return B.buildBr(bb)
      default:
        return B.buildUnreachable()
      }
    }
  }

  func visitCopyValueOp(_ op: CopyValueOp) -> IRValue {
    return trace("emitting LLVM IR for copy_value '\(op)'") {
      return B.buildUnreachable()
    }
  }

  func visitDestroyValueOp(_ op: DestroyValueOp) -> IRValue {
    return trace("emitting LLVM IR for destroy_value '\(op)'") {
      return B.buildUnreachable()
    }
  }

  func visitFunctionRefOp(_ op: FunctionRefOp) -> IRValue {
    return trace("emitting LLVM IR for function_ref '\(op)'") {
      return blockMap[op.function]!
    }
  }

  func visitSwitchConstrOp(_ op: SwitchConstrOp) -> IRValue {
    return trace("emitting LLVM IR for switch_constr '\(op)'") {
      return B.buildUnreachable()
    }
  }

  func visitDataInitOp(_ op: DataInitOp) -> IRValue {
    return trace("emitting LLVM IR for data_init '\(op)'") {
      return B.buildUnreachable()
    }
  }

  func visitUnreachableOp(_ op: UnreachableOp) -> IRValue {
    return trace("emitting LLVM IR for unreachable '\(op)'") {
      return B.buildUnreachable()
    }
  }
}
