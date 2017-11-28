/// Graph.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

/// A graph structure capable of answering queries about precedence of keys and
/// values.
public final class DAG<K: Comparable & Hashable, T> {
  var map = [K: [T]]()
  var keys = [K]()
  var hasSortedKeys = true

  init() {}

  func addVertex(level prec: K, _ v: T) {
    guard self.map[prec] != nil else {
      self.map[prec] = [v]
      self.keys.append(prec)
      self.hasSortedKeys = false
      return
    }

    self.map[prec]!.append(v)
  }

  func tighter(than lim: K) -> [T] {
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
