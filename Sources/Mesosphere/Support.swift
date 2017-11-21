/// Support.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

extension Sequence {
  /// Searches the range [first, last) for two consecutive identical elements.
  ///
  /// Implementation matches that of `adjacent_find` from libC++.
  func adjacentFind(_ pred: (Element, Element) -> Bool) -> (Self.Element, Self.Element)? {
    var it = self.makeIterator()
    guard var first = it.next() else {
      return nil
    }

    while let next = it.next() {
      guard pred(first, next) else {
        first = next
        continue
      }
      return (first, next)
    }

    return nil
  }
}
