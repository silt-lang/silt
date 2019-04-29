/// SimplifyCFG.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography

final class SimplifyCFG: ScopePass {
  var worklistList = [Continuation?]()
  var worklistMap = [Continuation: Int]()
  var loopHeaders = Set<Continuation>()
  var jumpThreadedBlocks = [Continuation: Int]()

  func run(on scope: Scope) {
    for bb in scope.continuations {
      self.addToWorklist(bb)
    }

    while let BB = self.popWorklist() {
      guard !self.removeDeadContinuationIfNecessary(scope, BB) else {
        continue
      }

      guard let terminalOp = BB.terminalOp else {
        fatalError()
      }

      switch terminalOp.opcode {
      case .apply:
        let op = terminalOp as! ApplyOp
        switch op.callee {
        case let funcRef as FunctionRefOp:
          return self.simplifyBranchBlock(op, funcRef)
        default:
          break
        }
      default:
        break
      }
    }
  }

  func simplifyBranchBlock(_ apply: ApplyOp, _ dest: FunctionRefOp) {
    // FIXME
  }

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

  func removeDeadContinuationIfNecessary(_ scope: Scope, _ cont: Continuation) -> Bool {
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

  func addToWorklist(_ cont: Continuation) {
    guard self.worklistMap[cont] == nil else {
      return
    }

    self.worklistList.append(cont)
    self.worklistMap[cont] = worklistList.count
  }

  func removeFromWorklist(_ BB: Continuation) {
    guard let It = self.worklistMap[BB] else {
      return
    }

    assert(worklistList[It-1] === BB, "Consistency error")
    self.worklistList[It-1] = nil


    // Remove it from the map as well.
    self.worklistMap.removeValue(forKey: BB)

    self.loopHeaders.remove(BB)
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
