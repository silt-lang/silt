/// Definition.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

/// A definition is a value with a type that may be referencded by another part
/// of the program.
public class Definition: Hashable {
  private static var idPool: Int = Int.min
  private let id: Int

  /// The operands applied to this definition.
  ///
  /// Constants will be applied to zero operands.
  public var operands : [Definition]
  /// The type of this definition.
  public let type: TypeBase
  /// The known uses of this value in the rest of the progam.
  public var uses: Set<Use> = []

  init(type: TypeBase) {
    defer { Definition.idPool += 1 }
    self.id = Definition.idPool

    self.operands = []
    self.type = type
  }

  public static func == (lhs: Definition, rhs: Definition) -> Bool {
    return lhs.id == rhs.id
  }

  public var hashValue: Int { return self.id }

  /// Returns the "order" of the type of this definition.
  ///
  /// Values have order 0, functions of values have order 1, functions of
  /// functions of values have order 2, etc.
  public var order: Int {
    return self.type.order
  }

  /// The context associated with this definition.
  public var context: Context {
    return self.type.context
  }

  @discardableResult
  func setOperand(at index: Int, to def: Definition) -> Definition {
    self.operands[index] = def
    let selfUse = Use(index: index, def: self)
    assert(def.uses.insert(selfUse).inserted)
    return def
  }
}

/// A Use represents a use of a definition in the program.
public struct Use: Hashable {
  let index : Int
  let definition : Definition

  init(index: Int, def: Definition) {
    self.index = index
    self.definition = def
  }

  public var hashValue: Int {
    return self.index ^ self.definition.hashValue
  }

  public static func == (lhs: Use, rhs: Use) -> Bool {
    return lhs.index == rhs.index
      && lhs.definition === rhs.definition
  }
}


