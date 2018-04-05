/// Graph.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// Represents an abstraction over graph-like objects.
public protocol GraphNode: AnyObject, Hashable {
  /// The successor sequence type for this node.
  associatedtype Successors: Sequence where Successors.Element == Self
  associatedtype Predecessors: Sequence where Predecessors.Element == Self

  /// A sequence of this node's successors.
  var successors: Successors { get }

  /// A sequence of this node's predecessors.
  var predecessors: Predecessors { get }
}

/// A sequence that computes the reverse post-order traversal of a given graph.
public struct ReversePostOrderSequence<Node: GraphNode>: Sequence {
  public struct Iterator: IteratorProtocol {
    let mayVisit: Set<Node>
    var visited = Set<Node>()
    var postorder = [Node]()
    fileprivate var nodeIndices = [Node: Int]()

    init(start: Node, mayVisit: Set<Node>) {
      self.mayVisit = mayVisit
      traverse(start)
    }

    /// Traverses the tree and builds a post-order traversal, which will be
    /// reversed on iteration.
    mutating func traverse(_ node: Node) {
      visited.insert(node)
      for child in node.successors {
        guard mayVisit.contains(child) && !visited.contains(child) else {
          continue
        }
        traverse(child)
      }
      nodeIndices[node] = postorder.count
      postorder.append(node)
    }

    public mutating func next() -> Node? {
      return postorder.popLast()
    }
  }

  public struct Indexer {
    var indices: [Node: Int]

    public func index(of node: Node) -> Int {
      guard let index = indices[node] else {
        fatalError("Requested index of node outside of this CFG")
      }
      return index
    }
  }

  let root: Node
  let mayVisit: Set<Node>

  public init(root: Node, mayVisit: Set<Node>) {
    self.root = root
    self.mayVisit = mayVisit
  }

  public func makeIterator() -> ReversePostOrderSequence<Node>.Iterator {
    return Iterator(start: root, mayVisit: mayVisit)
  }

  public func makeIndexer() -> Indexer {
    let it = Iterator(start: root, mayVisit: mayVisit)
    return Indexer(indices: it.nodeIndices)
  }
}
