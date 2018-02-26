/// CFG.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

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

