/// SimplifyCFG.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography

/// Performs dead code elimination and continuation merging.
///
/// - Removes continuations with no predecessors.
/// - Merges a continuation into its predecessor if there is only one and the
///   predecessor has only one successsor.
final class SimplifyCFG: ScopePass {
  var worklistList = [Continuation?]()
  var worklistMap = [Continuation: Int]()
  var loopHeaders = Set<Continuation>()
  var jumpThreadedBlocks = [Continuation: Int]()

  func run(on scope: Scope) {
    for cont in scope.continuations {
      self.addToWorklist(cont)
    }

    while let cont = self.popWorklist() {
      guard !self.removeDeadContinuationIfNecessary(scope, cont) else {
        continue
      }

      guard let terminalOp = cont.terminalOp else {
        fatalError()
      }

      switch terminalOp.opcode {
      case .apply:
        // swiftlint:disable force_cast
        let op = terminalOp as! ApplyOp
        switch op.callee {
        case let funcRef as FunctionRefOp:
          return self.simplifyBranchBlock(scope, cont, op, funcRef)
        default:
          break
        }
      default:
        break
      }
    }
  }
}

// MARK: Simplify Branch Blocks

extension SimplifyCFG {
  // Simplifies an unconditional branch from a dominator continuation to its
  // unique successor by merging the continuations.
  //
  //     bb0(%0, %1, ...):
  //       %dest = function_ref @bbN
  //       apply %dest(%0  %1  %2  ...)
  //
  //     ...
  //
  //     bbN(%n, %n+1, ...):
  //       %inst = ...
  //       ...
  //       <terminator>
  //
  // ===>
  //
  //     bb0(%0, %1, ...):
  //       %inst = ...
  //       ...
  //       <terminator>
  func simplifyBranchBlock(
    _ scope: Scope,
    _ cont: Continuation,
    _ apply: ApplyOp,
    _ dest: FunctionRefOp
  ) {
    // FIXME: Simplify the branch's operand values.

    let destCont = dest.function

    // If this block branches to a block with a single predecessor, then
    // merge the DestBB into this BB.
    if cont !== destCont && destCont.singlePredecessor != nil {
      // If there are any BB arguments in the destination, replace them with the
      // branch operands, since they must dominate the dest block.
      for i in 0..<apply.arguments.count {
        if destCont.parameters[i] !== apply.arguments[i].value {
          let val = apply.arguments[i].value
          destCont.parameters[i].replaceAllUsesWith(val)
        }
      }
    }

    // Reset the terminal op from the dominant block with the destination's
    // terminal operation.  This has the effect of migrating all its
    // instructions into this block when we schedule it.
    cont.terminalOp = destCont.terminalOp

    // Revisit this block now that we've changed it and remove the DestBB.
    self.addToWorklist(cont)

    // Look in the successors of the merged block for more opportunities.
    for succ in cont.successors {
      self.addToWorklist(succ)
    }

    // If the destination continuation was a loop header, the parent
    // continuation is now one too.
    if self.loopHeaders.contains(destCont) {
      self.loopHeaders.insert(cont)
    }

    self.removeFromWorklist(destCont)
    self.removeDeadContinuation(scope, destCont)
  }
}

// MARK: Simplify Switch Instructions

extension SimplifyCFG {
  func simplifySwitchConstr(
    _ scope: Scope,
    _ cont: Continuation,
    _ inst: SwitchConstrOp
  ) -> Bool {
    guard let selector = self.digForSelector(inst.matchedValue, cont) else {
      return false
    }

    let selectorDest = digForSelectorDestination(inst, selector)

    var droppedLiveBlock = false
    var destinationss = [Continuation]()
    for succ in inst.successors {
      guard let succCont = succ.parent else {
        continue
      }
      if succCont === selectorDest && !droppedLiveBlock {
        droppedLiveBlock = true
        continue
      }
      destinationss.append(succCont)
    }

    let DIO = inst.matchedValue as? DataInitOp
    let B = GIRBuilder(module: scope.module)
    if selectorDest.parameters.isEmpty {
      let payLoad: Value
      if let dio = DIO {
        payLoad = dio.argumentTuple!
      } else {
        let type = scope
                    .module
                    .typeConverter
                    .getPayloadTypeOfConstructors(rawName: selector)
        payLoad = B.createDataExtract(selector, inst.matchedValue,
                                            type)
      }
      _ = B.createApply(cont, selectorDest, [ payLoad ])
    } else {
      _ = B.createApply(cont, selectorDest, [])
    }

    self.addToWorklist(cont)

    for dest in destinationss {
      self.addToWorklist(dest)
      for pred in dest.predecessors {
        self.addToWorklist(pred)
      }
    }
    self.addToWorklist(selectorDest)
    return true
  }

  private func digForSelector(_ Val: Value, _ cont: Continuation) -> String? {
    // FIXME: Locate up to the data_init instruction
    return nil
  }

  private func digForSelectorDestination(
    _ inst: SwitchConstrOp,
    _ sel: String
    ) -> Continuation {
    guard let pat = inst.patterns.first(where: { $0.pattern == sel }) else {
      guard let defCont = inst.default else {
        fatalError()
      }
      return defCont.function
    }

    return pat.destination.function
  }
}

// MARK: Removing Continuations

extension SimplifyCFG {
  func removeDeadContinuation(_ scope: Scope, _ cont: Continuation) {
    // Clear the users of continuation's parameters.
    for op in cont.parameters {
      for use in op.users {
        use.drop()
      }
    }
    scope.remove(cont)
    scope.module.removeContinuation(cont)
  }

  func removeDeadContinuationIfNecessary(
    _ scope: Scope,
    _ cont: Continuation
  ) -> Bool {
    guard scope.entry !== cont else {
      return false
    }

    guard !cont.hasPredecessors else {
      return false
    }

    self.removeFromWorklist(cont)

    // Add successor blocks to the worklist since their predecessor list is
    // about to change.
    for successor in cont.successors {
      self.addToWorklist(successor)
    }

    self.removeDeadContinuation(scope, cont)
    return true
  }
}

// MARK: Worklist Bookkeeping

extension SimplifyCFG {
  func addToWorklist(_ cont: Continuation) {
    guard self.worklistMap[cont] == nil else {
      return
    }

    self.worklistList.append(cont)
    self.worklistMap[cont] = worklistList.count
  }

  func removeFromWorklist(_ cont: Continuation) {
    guard let entry = self.worklistMap[cont] else {
      return
    }

    assert(self.worklistList[entry-1] === cont)
    self.worklistList[entry-1] = nil


    // Remove it from the map as well.
    self.worklistMap.removeValue(forKey: cont)

    self.loopHeaders.remove(cont)
  }

  func popWorklist() -> Continuation? {
    while !self.worklistList.isEmpty {
      if let BB = self.worklistList.popLast(), BB != nil {
        self.worklistMap.removeValue(forKey: BB!)
        return BB
      }
    }
    return nil
  }
}
