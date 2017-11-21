/// Continuation.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

/// A continuation represents a function that, once called, never returns.  Its
/// body consists solely of primitive operations and calls to other
/// continuations.
public class Continuation: Definition {
  public class Parameter: Definition {
    weak var parent: Continuation?
    let index: Int

    init(type: TypeBase, continuation: Continuation, index: Int) {
      self.parent = continuation
      self.index = index
      super.init(type: type)
    }
  }

  /// The argument parameters to this continuation.
  public var parameters: [Parameter] = []

  init(_ fn: FunctionType) {
    super.init(type: fn)
    self.parameters.reserveCapacity(fn.operands.count)
  }

  public var callee: Definition {
    if self.operands.isEmpty {
      fatalError()
    }
    return self.operands[0]
  }

  public var arguments: [Definition] {
    if self.operands.count == 0 {
      return []
    }
    return self.operands.dropFirst().map{$0}
  }

  func computeSuccessors(direct: Bool, indirect: Bool) -> [Continuation] {
    var succs = [Continuation]()
    var queue = [Definition]()
    var done: Set<Definition> = []

    let enqueue = { (def: Definition) in
      if !done.contains(def) {
        queue.append(def)
        done.insert(def)
      }
    }

    done.insert(self)

    if direct && !self.operands.isEmpty {
      enqueue(self.callee)
    }

    if indirect {
      for arg in self.arguments {
        enqueue(arg)
      }
    }

    while !queue.isEmpty{
      let def = queue.removeFirst()
      if let continuation = def as? Continuation {
        succs.append(continuation)
        continue
      }

      for op in def.operands {
        if op.order >= 1 {
          enqueue(op)
        }
      }
    }

    return succs
  }

  func computePredecessors(direct: Bool, indirect: Bool) -> [Continuation] {
    var preds = [Continuation]()
    var queue = [Use]()
    var done: Set<Definition> = []

    let enqueue = { (def: Definition) in
      for use in def.uses {
        if !done.contains(def) {
          queue.append(use)
          done.insert(use.definition)
        }
      }
    }

    enqueue(self)

    while !queue.isEmpty{
      let use = queue.removeFirst()
      if let continuation = use.definition as? Continuation {
        if (use.index == 0 && direct) || (use.index != 0 && indirect) {
          preds.append(continuation)
        }
        continue
      }

      enqueue(use.definition)
    }

    return preds
  }
}

public class TerminatorContinuation: Continuation {}

