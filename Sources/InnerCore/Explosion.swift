/// Explosion.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import LLVM

/// The representation for an explosion is just a list of raw LLVM
/// values.  The meaning of these values is imposed externally by the
/// type infos, except that it is expected that they will be passed
/// as arguments in exactly this way.
final class Explosion {
  private(set) var nextValue: Int
  private(set) var values: [IRValue]

  init() {
    self.nextValue = 0
    self.values = []
  }

  deinit {
    precondition(self.isEmpty, "explosion had values remaining when destroyed!")
  }

  var isEmpty: Bool {
    return self.nextValue == self.values.count
  }

  var count: Int {
    return self.values.count - nextValue
  }

  // FIXME: This is a horrible horrible thing to support non-consuming switches
  // over scalar values like natural numbers.
  func peek() -> IRValue {
    return self.values[self.nextValue]
  }

  func append(_ value: IRValue) {
    assert(nextValue == 0, "adding to partially-claimed explosion?")
    self.values.append(value)
  }

  func append<S>(contentsOf values: S)
    where S: Sequence, S.Element == IRValue {
    assert(nextValue == 0, "adding to partially-claimed explosion?")
    self.values.append(contentsOf: values)
  }

  /// The next N values have been claimed in some indirect way (e.g.
  /// using getRange() and the like); just give up on them.
  func markClaimed(_ n: Int) {
    assert(self.nextValue + n <= self.values.count)
    self.nextValue += n
  }

  /// Claim and return the next value in this explosion.
  func claimSingle() -> IRValue {
    assert(self.nextValue < self.values.count, "No values left to claim")
    defer { self.nextValue += 1 }
    return self.values[self.nextValue]
  }

  /// Claim and return the next N values in this explosion.
  func claim(next n: Int? = nil) -> ArraySlice<IRValue> {
    let n = n ?? self.count
    assert(self.nextValue + n <= self.values.count)
    defer { self.nextValue += n }
    return self.values[self.nextValue..<self.nextValue+n]
  }

  func transfer(into other: Explosion, _ n: Int) {
    other.append(contentsOf: self.claim(next: n))
  }

  func emplace(_ other: Explosion) {
    self.nextValue = other.nextValue
    self.values.removeAll()
    self.append(contentsOf: other.claim())
  }
}

extension Explosion {
  /// An explosion schema is essentially the type of an Explosion.
  struct Schema {
    // The schema for one atom of the explosion
    enum Element {
      case scalar(IRType)
      case aggregate(IRType, Alignment)

      var isAggregate: Bool {
        switch self {
        case .aggregate(_, _):
          return true
        default:
          return false
        }
      }

      var isScalar: Bool {
        switch self {
        case .scalar(_):
          return true
        default:
          return false
        }
      }

      var scalarType: IRType {
        switch self {
        case let .scalar(type):
          return type
        default:
          fatalError("Cannot retrieve scalar type from aggregate element!")
        }
      }

      var getAggregateType: IRType {
        switch self {
        case let .aggregate(type, _):
          return type
        default:
          fatalError("Cannot retrieve aggregate type from scalar element!")
        }
      }
    }

    let elements: [Element]
    let containsAggregate: Bool

    fileprivate init(_ elements: [Element], _ containsAggregate: Bool) {
      self.elements = elements
      self.containsAggregate = containsAggregate
    }

    var isEmpty: Bool {
      return self.elements.isEmpty
    }

    var count: Int {
      return self.elements.count
    }

    subscript(_ index: Int) -> Element {
      return self.elements[index]
    }

    func getScalarResultType(_ IGM: IRGenModule) -> IRType {
      guard !self.isEmpty else {
        return VoidType()
      }

      guard self.count > 1 else {
        switch self.elements[0] {
        case let .scalar(type):
          return type
        default:
          fatalError("element with 1 element should be scalar!")
        }
      }

      let elts = self.elements.map { (element) -> IRType in
        switch element {
        case let .scalar(type):
          return type
        default:
          fatalError("element may only have scalar type!")
        }
      }
      return StructType(elementTypes: elts, in: IGM.module.context)
    }
  }
}

extension Explosion.Schema {
  final class Builder {
    var elements: [Element]
    var containsAggregate: Bool = false

    init() {
      self.elements = []
      self.containsAggregate = false
    }

    func append(_ e: Element) {
      self.elements.append(e)
      self.containsAggregate = self.containsAggregate || e.isAggregate
    }

    func finalize() -> Explosion.Schema {
      return Explosion.Schema(self.elements, self.containsAggregate)
    }
  }
}
