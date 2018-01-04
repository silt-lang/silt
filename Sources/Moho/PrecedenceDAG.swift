/// PrecedenceDAG.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

/// A graph structure capable of answering queries about precedence of keys and
/// values.
public final class PrecedenceDAG<K: Comparable & Hashable, T> {
  private var map = [K: [T]]()
  private var keys = [K]()
  private var hasSortedKeys = true

  /// Creates and initializes a new empty `PrecedenceDAG`.
  public init() {}

  /// Adds a vertex to the DAG at the specified level.
  public func addVertex(level prec: K, _ v: T) {
    guard self.map[prec] != nil else {
      self.map[prec] = [v]
      self.keys.append(prec)
      self.hasSortedKeys = false
      return
    }

    self.map[prec]!.append(v)
  }

  /// Retrieves all vertices with the given precedence.
  public subscript(_ key: K) -> [T] {
    return self.map[key, default: []]
  }

  /// A Boolean value indicating whether the DAG is empty.
  public var isEmpty: Bool {
    return self.keys.isEmpty
  }

  /// Retrieves the loosest precedence in the DAG, if it exists.
  public var loosest: K? {
    if !self.hasSortedKeys {
      self.keys.sort()
      self.hasSortedKeys = true
    }
    return self.keys.first
  }

  /// Retrieves the tightest precedence in the DAG, if it exists.
  public var tightest: K? {
    if !self.hasSortedKeys {
      self.keys.sort()
      self.hasSortedKeys = true
    }
    return self.keys.last
  }

  /// Retrieves all vertices that binds strictly tighter than the given level
  /// in ascending order of precedence.
  public func tighter(than lim: K) -> [T] {
    if !self.hasSortedKeys {
      self.keys.sort()
      self.hasSortedKeys = true
    }

    var tighter = [T]()
    for k in self.keys {
      guard k > lim else {
        continue
      }
      tighter += self.map[k]!
    }
    return tighter
  }
}
