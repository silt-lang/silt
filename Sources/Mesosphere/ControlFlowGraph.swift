/// ControlFlowGraph.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.


protocol Direction {} /*{*/
  enum Forward: Direction {}
  enum Backward: Direction {}
/*}*/

final class ControlFlowGraph<Dir: Direction> {
  var nodes = [Continuation: ControlFlowNode]()
  let scope: Scope

  let entry: ControlFlowNode
  let exit: ControlFlowNode

  init(scope: Scope) {
    self.scope = scope
    self.entry = ControlFlowNode(continuation: scope.entry)
    self.exit = ControlFlowNode(continuation: scope.exit)

    self.nodes[scope.entry] = self.entry
    self.nodes[scope.exit] = self.exit

    var cfgQueue = [Continuation]()
    var cfgDone = Set<Continuation>()
    let cfgEqueue = { (cont: Continuation) in
      if cfgDone.insert(cont).inserted {
        cfgQueue.append(cont)
      }
    }

    cfgQueue.append(scope.entry)
    while !cfgQueue.isEmpty {
      let src = cfgQueue.removeFirst()

      var queue = [Definition]()
      var done = Set<Definition>()

      let enqueue = { (def: Definition) in
        if def.order > 0 && scope.contains(def) && done.insert(def).inserted {
          if let destination = def as? Continuation {
            cfgEqueue(destination)

            self.getOrCreateCFNode(continuation: src)
              .link(to: self.getOrCreateCFNode(continuation: destination))
          } else {
            queue.append(def)
          }
        }
      }

      queue.append(src)

      while !queue.isEmpty {
        let def = queue.removeFirst()
        for op in def.operands {
          enqueue(op)
        }
      }
    }

    linkToExit()
    verify()
  }

  func linkToExit() {
    var reachable = Set<ControlFlowNode>()
    var queue = [ControlFlowNode]()

    for (_, n) in self.nodes {
      if n != self.exit && n.successors.isEmpty {
        n.link(to: self.exit)
      }
    }

    let enqueueBackwardsReachableNode = { (n: ControlFlowNode) in
      let enqueue = { (n: ControlFlowNode) in
        if reachable.insert(n).inserted {
          queue.append(n)
        }
      }
      enqueue(n)

      while !queue.isEmpty {
        let item = queue.removeFirst()
        for pred in item.predecessors {
          enqueue(pred)
        }
      }
    }

    var stack = [ControlFlowNode]()
    var onStack = Set<ControlFlowNode>()

    let push = { (n: ControlFlowNode) -> Bool in
      if onStack.insert(n).inserted {
        stack.append(n)
        return true
      }
      return false
    }

    enqueueBackwardsReachableNode(self.exit)
    _ = push(self.entry)

    while !stack.isEmpty {
      let n = stack.last!
      var todo = false
      for succ in n.successors {
        todo = todo || push(succ)
      }

      if !todo {
        if !reachable.contains(n) {
          n.link(to: self.exit)
          enqueueBackwardsReachableNode(n)
        }
        _ = stack.popLast()
      }
    }
  }

  func getOrCreateCFNode(continuation: Continuation) -> ControlFlowNode {
    guard let n = self.nodes[continuation] else {
      let node = ControlFlowNode(continuation: continuation)
      self.nodes[continuation] = node
      return node
    }
    return n
  }

  private func verify() {
    var error = false
    for (_, inn) in self.nodes {
      if inn != self.entry && inn.predecessors.isEmpty {
        print("missing predecessors: \(inn.continuation)")
        error = true
      }
    }

    if error {
      fatalError("CFG not sound")
    }
  }
}

public class ControlFlowNode: Hashable {
  private static var idPool: Int = Int.min
  private let id: Int

  public let continuation: Continuation

  var predecessors: Set<ControlFlowNode> = []
  var successors: Set<ControlFlowNode> = []

  init(continuation: Continuation) {
    defer { ControlFlowNode.idPool += 1 }
    self.id = ControlFlowNode.idPool

    self.continuation = continuation
  }

  public var hashValue: Int { return self.id }
  public static func == (lhs: ControlFlowNode, rhs: ControlFlowNode) -> Bool {
    return lhs === rhs
  }

  func link(to other: ControlFlowNode) {
    self.successors.insert(other)
    other.predecessors.insert(self)
  }
}
