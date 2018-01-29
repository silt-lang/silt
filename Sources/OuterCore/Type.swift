/// Type.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Moho

public class Type: Hashable {
  public static func ==(lhs: Type, rhs: Type) -> Bool {
    return lhs.equals(rhs)
  }

  public func equals(_ other: Type) -> Bool {
    return self === other
  }

  public var hashValue: Int {
    return "\(ObjectIdentifier(self).hashValue)".hashValue
  }
}

public final class TypeMetadataType: Type {
  public unowned let type: Type

  init(type: Type) {
    self.type = type
  }

  public override func equals(_ other: Type) -> Bool {
    guard let other = other as? TypeMetadataType else { return false }
    return type == other.type
  }

  public override var hashValue: Int {
    return type.hashValue ^ 0xbab8394b
  }
}

public final class DataType: Type {
  public struct Constructor: Hashable {
    public let name: QualifiedName
    public unowned let type: Type

    public init(name: QualifiedName, type: Type) {
      self.name = name
      self.type = type
    }

    public static func ==(lhs: Constructor, rhs: Constructor) -> Bool {
      return lhs.name == rhs.name && lhs.type == rhs.type
    }

    public var hashValue: Int {
      return name.string.hashValue ^ ObjectIdentifier(type).hashValue
    }
  }
  public let name: QualifiedName
  public private(set) var constructors = [Constructor]()

  init(name: QualifiedName) {
    self.name = name
  }

  public func addConstructor(name: QualifiedName, type: Type) {
    constructors.append(Constructor(name: name, type: type))
  }

  public override func equals(_ other: Type) -> Bool {
    guard let other = other as? DataType else { return false }
    return name == other.name && constructors == other.constructors
  }

  public override var hashValue: Int {
    var h = name.hashValue
    for constr in constructors {
      h ^= constr.hashValue
    }
    return h
  }
}

public final class RecordType: Type {
  public struct Field: Hashable {
    public let name: QualifiedName
    public unowned let type: Type

    public init(name: QualifiedName, type: Type) {
      self.name = name
      self.type = type
    }

    public static func ==(lhs: Field, rhs: Field) -> Bool {
      return lhs.name == rhs.name && lhs.type === rhs.type
    }

    public var hashValue: Int {
      return name.string.hashValue ^ ObjectIdentifier(type).hashValue
    }
  }
  public let name: QualifiedName
  public private(set) var fields = [Field]()

  init(name: QualifiedName) {
    self.name = name
  }

  public func addField(name: QualifiedName, type: Type) {
    fields.append(Field(name: name, type: type))
  }

  public override func equals(_ other: Type) -> Bool {
    guard let other = other as? RecordType else { return false }
    return name == other.name && fields == other.fields
  }

  public override var hashValue: Int {
    var h = name.hashValue
    for field in fields {
      h ^= field.hashValue
    }
    return h
  }
}

public final class FunctionType: Type {
  public let arguments: [Type]
  public let returnType: Type

  init(arguments: [Type], returnType: Type) {
    self.arguments = arguments
    self.returnType = returnType
  }

  public override func equals(_ other: Type) -> Bool {
    guard let other = other as? FunctionType else { return false }
    for (lhsArg, rhsArg) in zip(arguments, other.arguments) {
      guard lhsArg === rhsArg else { return false }
    }
    return returnType === other.returnType
  }

  public override var hashValue: Int {
    var h = returnType.hashValue
    for arg in arguments {
      h ^= arg.hashValue
    }
    return h ^ 0xab372bfa
  }
}

public final class BottomType: Type {
  public override func equals(_ other: Type) -> Bool {
    return other is BottomType
  }
  public override var hashValue: Int {
    return 0
  }
}
