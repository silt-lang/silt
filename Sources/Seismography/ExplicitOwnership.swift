/// ExplicitOwnership.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// Holds an unowned reference to a class (this class is necessary for keeping
/// unowned references in collection types.
struct Unowned<T: AnyObject & Hashable>: Hashable {
  unowned let value: T

  static func == <T>(lhs: Unowned<T>, rhs: Unowned<T>) -> Bool {
    return lhs.value == rhs.value
  }

  var hashValue: Int {
    return value.hashValue
  }
}

/// A dictionary type that holds unowned references to both keys and values.
public struct UnownedDictionary<
  Key: AnyObject & Hashable,
  Value: AnyObject & Hashable
>: Collection, Hashable {
  public typealias Index = UnownedDictionaryIndex

  public struct UnownedDictionaryIndex: Comparable {
    // swiftlint:disable syntactic_sugar
    let underlying: Dictionary<Unowned<Key>, Unowned<Value>>.Index

    public static func < (lhs: UnownedDictionaryIndex,
                          rhs: UnownedDictionaryIndex) -> Bool {
      return lhs.underlying < rhs.underlying
    }
    public static func == (lhs: UnownedDictionaryIndex,
                           rhs: UnownedDictionaryIndex) -> Bool {
      return lhs.underlying == rhs.underlying
    }
  }

  var storage: [Unowned<Key>: Unowned<Value>]

  public init() {
    storage = [:]
  }

  public init(_ values: [Key: Value]) {
    var storage = [Unowned<Key>: Unowned<Value>]()
    for (k, v) in values {
      storage[Unowned(value: k)] = Unowned(value: v)
    }
    self.storage = storage
  }

  public var startIndex: Index {
    return UnownedDictionaryIndex(underlying: storage.startIndex)
  }

  public var endIndex: Index {
    return UnownedDictionaryIndex(underlying: storage.endIndex)
  }

  public subscript(position: Index) -> (key: Key, value: Value) {
    let bucket = storage[position.underlying]
    return (key: bucket.key.value, value: bucket.value.value)
  }

  public subscript(key: Key) -> Value? {
    get {
      return storage[Unowned(value: key)]?.value
    }
    set {
      storage[Unowned(value: key)] = newValue.map(Unowned.init)
    }
  }

  public func index(after i: Index) -> Index {
    return UnownedDictionaryIndex(underlying:
      storage.index(after: i.underlying))
  }

  public static func == <K, V>(lhs: UnownedDictionary<K, V>,
                               rhs: UnownedDictionary<K, V>) -> Bool {
    return lhs.storage == rhs.storage
  }

  public var hashValue: Int {
    return storage.reduce(0) { $0 ^ $1.key.hashValue ^ $1.value.hashValue }
  }
}

/// An array of unowned references to values. Use this in place of an array if
/// you don't want the elements of the array to be owned values.
public struct UnownedArray<
  Element: AnyObject & Hashable
>: Collection, Hashable {
  var storage: [Unowned<Element>]

  public init() {
    storage = []
  }

  public init(values: [Element]) {
    self.storage = values.map(Unowned.init)
  }

  public var startIndex: Int {
    return storage.startIndex
  }

  public var endIndex: Int {
    return storage.endIndex
  }

  public mutating func append(_ element: Element) {
    storage.append(Unowned(value: element))
  }

  public subscript(position: Int) -> Element {
    get {
      return storage[position].value
    }
    set {
      return storage[position] = Unowned(value: newValue)
    }
  }

  public func index(after i: Int) -> Int {
    return storage.index(after: i)
  }

  public static func == (lhs: UnownedArray, rhs: UnownedArray) -> Bool {
    return lhs.storage == rhs.storage
  }

  public var hashValue: Int {
    return storage.reduce(0) { $0 ^ $1.hashValue }
  }
}
