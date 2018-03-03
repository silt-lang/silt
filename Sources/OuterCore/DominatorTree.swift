/// DominatorTree.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

final class DominatorTree {
  var doms = [Continuation: Continuation]()
  var children = [Continuation: [Continuation]]()
  var depthMap = [Continuation: Int]()

  init(_ root: Continuation) {
    // Cooper et al, 2001. A Simple, Fast Dominance Algorithm. http://www.cs.rice.edu/~keith/EMBED/dom.pdf

    let rpoIndexer = root.reversePostOrder.makeIndexer()
    for n in root.reversePostOrder.dropFirst() {
      for pred in n.predecessors {
        guard rpoIndexer.index(of: pred) < rpoIndexer.index(of: n) else {
          continue
        }
        self.doms[n] = pred
        break
      }
    }

    var changed = true
    while changed {
      changed = false

      for n in root.reversePostOrder.dropFirst() {
        var new_idom: Continuation? = nil
        for pred in n.predecessors {
          guard let start_dom = new_idom else {
            new_idom = pred
            continue
          }
          new_idom = intersect(start_dom, pred, rpoIndexer)
        }

        if self.doms[n] != new_idom {
          self.doms[n] = new_idom
          changed = true
        }
      }
    }

    for n in root.reversePostOrder.dropFirst() {
      self.children[self.doms[n]!, default: []].append(n)
    }
    self.computeDepth(root, 0)
  }

  func depth(_ n: Continuation) -> Int {
    guard let result = self.depthMap[n] else {
      fatalError("Attempt to retrieve depth of node outside this CFG")
    }
    return result
  }

  private func computeDepth(_ n: Continuation, _ i: Int) {
    self.depthMap[n] = i
    for child in self.children[n, default: []] {
      computeDepth(child, i+1)
    }
  }

  typealias RPOIndexer = ReversePostOrderSequence<Continuation>.Indexer
  private func intersect(_ b1: Continuation, _ b2: Continuation, _ indexer: RPOIndexer) -> Continuation {
    var finger1 = b1
    var finger2 = b2
    while indexer.index(of: finger1) != indexer.index(of: finger2) {
      while indexer.index(of: finger1) < indexer.index(of: finger2) {
        finger2 = self.doms[finger2]!
      }
      while indexer.index(of: finger2) < indexer.index(of: finger1) {
        finger1 = self.doms[finger1]!
      }
    }
    return finger1
  }
}
