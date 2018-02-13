/// Value.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public class Value: Hashable {
  let name: String
  unowned var type: Value

  init(name: String, type: Value) {
    self.name = name
    self.type = type
  }

  /// All values are equatable and hashable using reference equality and
  /// the hash of their ObjectIdentifiers.

  public static func ==(lhs: Value, rhs: Value) -> Bool {
    return lhs.equals(rhs)
  }

  public func equals(_ other: Value) -> Bool {
    return self === other
  }

  public var hashValue: Int {
    return "\(ObjectIdentifier(self).hashValue)".hashValue
  }
}

public class Parameter: Value {
  unowned let parent: Continuation
  let index: Int

  init(parent: Continuation, index: Int, type: Value, name: String) {
    self.parent = parent
    self.index = index
    super.init(name: name, type: type)
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
