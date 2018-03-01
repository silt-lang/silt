/// Value.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public class Value: Hashable {
  let name: String
  var type: Value


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

  open func dump() {
    fatalError()
  }
}

public enum Ownership {
  case borrowed
  case owned
}

public class Parameter: Value {
  unowned let parent: Continuation
  let index: Int
  let ownership: Ownership

  init(parent: Continuation, index: Int, type: Value, ownership: Ownership,
       name: String) {
    self.parent = parent
    self.index = index
    self.ownership = ownership
    super.init(name: name, type: type)
  }

  var isOwned: Bool {
    return ownership == .owned
  }
  var isBorrowed: Bool {
    return ownership == .borrowed
  }

  public override func dump() {
    print("%\(self.index) : \(self.type)", terminator: "")
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
  var nextUse: Operand? = nil

  /// A back-pointer in the use-chain, required for fast patching
  /// of use-chains.
  weak var back: Operand? = nil

  /// The owner of this operand.
  /// FIXME: this could be space-compressed.
  var owningOp: PrimOp?

  init(owner: PrimOp, value: Value) {
    self.value = value
    self.owningOp = owner
    
    self.insertIntoCurrent()
  }

  deinit {
    self.removeFromCurrent()
  }

  public static func ==(lhs: Operand, rhs: Operand) -> Bool {
    return lhs.value == rhs.value
  }

  public var hashValue: Int {
    return self.value.hashValue
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

  public func dump() {
    self.value.dump()
  }
}
