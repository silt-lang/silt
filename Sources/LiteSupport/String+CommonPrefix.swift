/// String+CommonPrefix.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

extension Array where Element == String {
  /// Finds a common prefix string of all strings in this array.
  /// - Complexity: O(m * n) where m is the length of the first string in the
  ///               array, and n is the length of the array.
  var commonPrefix: String {
    if isEmpty { return "" }
    var mutStrings = self
    var prefix = ""
    while let char = mutStrings[0].first {
      mutStrings[0].removeFirst()
      for i in mutStrings.indices.dropFirst() {
        guard let c = mutStrings[i].first, c == char else { return prefix }
        mutStrings[i].removeFirst()
      }
      prefix.append(char)
    }
    return prefix
  }
}
