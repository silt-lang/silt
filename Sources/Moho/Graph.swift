/// NameBinding.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

public final class DAG<K: Comparable & Hashable, T> {
  var map = [K: [T]]()
  var keys = [K]()
  var isSortedKeys = true

  init() {}

  func addVertex(level prec: K, _ v: T) {
    guard self.map[prec] != nil else {
      self.map[prec] = [v]
      self.keys.append(prec)
      isSortedKeys = false
      return
    }

    self.map[prec]!.append(v)
  }

  func tighter(than lim: K) -> [T] {
    if !isSortedKeys {
      self.keys.sort()
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
