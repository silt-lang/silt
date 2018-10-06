/// CFG.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

public final class Successor {
  /// The primop that contains this successor.
  public private(set) var containingInst: PrimOp?

  /// If non-null, this is the continuation that this continuation branches to.
  public private(set) var successor: Continuation?

  public private(set) weak var parent: Continuation?

  /// A pointer to the successor that represents the previous successors in the
  /// predecessor list for `successor`.
  ///
  /// - note: Must be `nil` if `successor` is.
  public private(set) weak var previous: Successor?

  /// A pointer to the successor that represents the next successor in the
  /// predecessor list for `successor`.
  ///
  /// - note: Must be `nil` if `successor` is.
  public private(set) var next: Successor?

  init(_ CI: PrimOp?) {
    self.containingInst = CI
  }

  init(_ parent: Continuation, _ CI: PrimOp?, _ successor: Continuation) {
    self.parent = parent
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

/// Uses the `Successor` node of a continuation to iterate over the
/// continuations that have terminators that branch to it.
public final class PredecessorIterator: IteratorProtocol {
  /// The current predecessor continuation at this iteration point, or nil if
  /// the predecessor list has been exhausted.
  public private(set) var continuation: Continuation?
  private var succ: Successor?

  init(_ succ: Successor) {
    self.succ = succ
    self.continuation = nil
    self.computeCurrentContinuation()
  }

  /// Returns the next continuation in the sequence, if any.
  public func next() -> Continuation? {
    guard let c = self.succ else {
      return nil
    }
    self.succ = c.next
    computeCurrentContinuation()
    return self.continuation
  }

  private func computeCurrentContinuation() {
    guard let cur = self.succ, cur.parent != nil else{
      self.continuation = nil
      return
    }
    self.continuation = cur.parent
    assert(self.continuation != nil)
  }
}
