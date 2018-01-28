/// Value.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public class Value: Hashable {
  let name: String

  init(name: String) {
    self.name = name
  }

  /// All values are equatable and hashable using reference equality and
  /// the hash of their ObjectIdentifiers.

  public static func ==(lhs: Value, rhs: Value) -> Bool {
    return lhs === rhs
  }

  public var hashValue: Int {
    return ObjectIdentifier(self).hashValue
  }
}

public class Parameter: Value {
  let parent: Continuation
  let index: Int
  let type: Type

  init(parent: Continuation, index: Int, type: Type, name: String) {
    self.parent = parent
    self.index = index
    self.type = type
    super.init(name: name)
  }
}

public enum Copy {
  case trivial
  case malloc
  case custom(Continuation)
}

public enum Destructor {
  case trivial
  case free
  case custom(Continuation)
}
