/// Graph.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// Represents an abstraction over graph-like objects.
public protocol Graph: AnyObject {
  /// The successor sequence type for this node.
  associatedtype Successors: Sequence where Successors.Element == Self

  /// A sequence of this node's successors.
  var successors: Successors { get }
}

public extension Graph {
  /// A sequence that iterates over the reverse post-order traversal of this
  /// graph.
  var reversePostOrder: ReversePostOrderSequence<Self> {
    return ReversePostOrderSequence(graph: self)
  }
}

/// A sequence that computes the reverse post-order traversal of a given graph.
public struct ReversePostOrderSequence<Node: Graph>: Sequence {
  public struct Iterator: IteratorProtocol {
    var visited = Set<ObjectIdentifier>()
    var postorder = [Node]()

    init(start: Node) {
      traverse(start)
    }

    /// Traverses the tree and builds a post-order traversal, which will be
    /// reversed on iteration.
    mutating func traverse(_ node: Node) {
      visited.insert(ObjectIdentifier(node))
      for child in node.successors {
        if visited.contains(ObjectIdentifier(child)) { continue }
        traverse(child)
      }
      postorder.append(node)
    }

    public mutating func next() -> Node? {
      return postorder.popLast()
    }
  }

  let graph: Node

  public func makeIterator() -> ReversePostOrderSequence<Node>.Iterator {
    return Iterator(start: graph)
  }
}