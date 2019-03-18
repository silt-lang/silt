/// Value.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Moho

public class Value: Hashable, ManglingEntity {
  public enum Category {
    case object
    case address
  }

  public private(set) var type: Value
  public let category: Value.Category

  init(type: Value, category: Value.Category) {
    self.type = type
    self.category = category
  }

  /// Query the type information of a GIR type to determine whether it is
  /// "trivial".
  ///
  /// Values of trivial type requires no further work to copy, move, or destroy.
  ///
  /// - Parameter module: The module in which the type resides.
  /// - Returns: `true` if the lowered type is trivial, else `false`.
  public func isTrivial(_ module: GIRModule) -> Bool {
    return module.typeConverter.lowerType(self).trivial
  }

  /// All values are equatable and hashable using reference equality and
  /// the hash of their ObjectIdentifiers.

  public static func == (lhs: Value, rhs: Value) -> Bool {
    return lhs.equals(rhs)
  }

  public func equals(_ other: Value) -> Bool {
    return self === other
  }

  public func hash(into hasher: inout Hasher) {
    "\(ObjectIdentifier(self).hashValue)".hash(into: &hasher)
  }

  fileprivate var firstUse: Operand?

  public var hasUsers: Bool {
    return self.firstUse != nil
  }

  public var users: AnySequence<Operand> {
    guard let first = self.firstUse else {
      return AnySequence<Operand>([])
    }
    return AnySequence<Operand>(sequence(first: first) { use in
      return use.nextUse
    })
  }

  public func replaceAllUsesWith(_ RHS: Value) {
    precondition(self !== RHS, "Cannot RAUW a value with itself")
    for user in self.users {
      user.value = RHS
    }
  }

  public func mangle<M: Mangler>(into mangler: inout M) {
    fatalError("Generic Value may not be mangled; this must be overriden")
  }
}

public class NominalValue: Value {
  public let name: QualifiedName
  public init(name: QualifiedName, type: Value, category: Value.Category) {
    self.name = name
    super.init(type: type, category: category)
  }

  public var baseName: String {
    return self.name.name.description
  }
}

public enum Ownership {
  case trivial
  case unowned
  case owned
}

public class Parameter: Value {
  unowned public let parent: Continuation
  public let index: Int
  public let ownership: Ownership = .owned

  init(parent: Continuation, index: Int, type: Value) {
    self.parent = parent
    self.index = index
    super.init(type: type, category: type.category)
  }

  public override func mangle<M: Mangler>(into mangler: inout M) {
    self.type.mangle(into: &mangler)
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

/// A formal reference to a value, suitable for use as a stored operand.
public final class Operand: Hashable {

  /// The next operand in the use-chain.  Note that the chain holds
  /// every use of the current ValueBase, not just those of the
  /// designated result.
  var nextUse: Operand?

  /// A back-pointer in the use-chain, required for fast patching
  /// of use-chains.
  weak var back: Operand?

  /// The owner of this operand.
  /// FIXME: this could be space-compressed.
  weak var owningOp: PrimOp?

  init(owner: PrimOp, value: Value) {
    self.value = value
    self.owningOp = owner

    self.insertIntoCurrent()
  }

  deinit {
    self.removeFromCurrent()
  }

  public static func == (lhs: Operand, rhs: Operand) -> Bool {
    return lhs.value == rhs.value
  }

  public func hash(into hasher: inout Hasher) {
    self.value.hash(into: &hasher)
  }

  /// The value used as this operand.
  public var value: Value {
    willSet {
      self.removeFromCurrent()
    }
    didSet {
      self.insertIntoCurrent()
    }
  }

  /// Remove this use of the operand.
  public func drop() {
    self.removeFromCurrent()
    self.nextUse = nil
    self.back = nil
    self.owningOp = nil
  }

  /// Return the user that owns this use.
  public var user: PrimOp {
    return self.owningOp!
  }

  private func removeFromCurrent() {
    guard let backPtr = self.back else {
      return
    }
    self.back = self.nextUse
    if let next = self.nextUse {
      next.back = backPtr
    }
  }

  private func insertIntoCurrent() {
    self.back = self.value.firstUse
    self.nextUse = self.value.firstUse
    if let next = self.nextUse {
      next.back = self.nextUse
    }
    self.value.firstUse = self
  }
}
