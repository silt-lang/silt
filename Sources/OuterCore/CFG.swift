//
//  CFG.swift
//  siltPackageDescription
//
//  Created by Robert Widmann on 2/20/18.
//

class CFG {
  var rpo = [Int: Continuation]()

  init(_ entry: Continuation, _ size: Int) {
    _ = self.postOrderVisit(entry, size)
  }

  func postOrderVisit(_ n : Continuation, _ i_ : Int) -> Int {
    var i = i_
    for succ in n.successors {
      if succ.forwardCFGIndex == -1 {
        i = postOrderVisit(succ, i)
      }
    }
    n.forwardCFGIndex = i - 1
    rpo[n.forwardCFGIndex] = n;
    return n.forwardCFGIndex
  }

  var reversePostOrder: [Continuation] {
    return self.rpo.values.sorted { lhs, rhs in
      lhs.forwardCFGIndex < rhs.forwardCFGIndex
    }
  }
}

public final class Successor {
  /// The primop that contains this successor.
  var containingInst: PrimOp?
  /// If non-null, this is the continuation that this continuation branches to.
  var successor: Continuation?
  /// A pointer to the successor that represents the previous successors in the
  /// predecessor list for `successor`.
  ///
  /// - note: Must be `nil` if `successor` is.
  weak var previous: Successor?
  /// A pointer to the successor that represents the next successor in the
  /// predecessor list for `successor`.
  ///
  /// - note: Must be `nil` if `successor` is.
  var next: Successor? = nil

  init(_ CI: PrimOp?) {
    self.containingInst = CI
  }

  init(_ CI: PrimOp?, _ successor: Continuation) {
    self.containingInst = CI
    self.setSuccessor(successor)
  }

  deinit {
    self.setSuccessor(nil)
  }

  func setSuccessor(_ succ: Continuation?) {
    guard succ !== self.successor else { return }

    // If we were already pointing to a basic block, remove ourself from its
    // predecessor list.
    if self.successor != nil {
      self.previous?.setSuccessor(self.next?.successor)
      if let next = self.next {
        next.previous = self.previous
      }
    }

    // If we have a successor, add ourself to its prev list.
    if let succ = succ {
      self.previous = succ.predecessorList
      self.next = succ.predecessorList
      if let next = self.next {
        next.previous = self.next
      }
      succ.predecessorList = self
    }
    self.successor = succ
  }
}
