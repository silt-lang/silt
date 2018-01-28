/// Type.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Moho

public protocol Type: AnyObject {}

public final class TypeMetadataType: Type, Hashable {
  public let type: Type

  init(type: Type) {
    self.type = type
  }

  public static func ==(lhs: TypeMetadataType, rhs: TypeMetadataType) -> Bool {
    return lhs.type === rhs.type
  }

  public var hashValue: Int {
    return ObjectIdentifier(type).hashValue ^ 0x4ab8394b
  }
}

public final class DataType: Type, Hashable {
  public struct Constructor: Hashable {
    public let name: QualifiedName
    public let type: Type

    public static func ==(lhs: Constructor, rhs: Constructor) -> Bool {
      return lhs.name == rhs.name && lhs.type === rhs.type
    }

    public var hashValue: Int {
      return name.string.hashValue ^ ObjectIdentifier(type).hashValue
    }
  }
  public let name: QualifiedName
  public let constructors: [Constructor]

  init(name: QualifiedName, constructors: [Constructor]) {
    self.name = name
    self.constructors = constructors
  }

  public static func ==(lhs: DataType, rhs: DataType) -> Bool {
    return lhs.name == rhs.name && lhs.constructors == rhs.constructors
  }

  public var hashValue: Int {
    var h = name.hashValue
    for constr in constructors {
      h ^= constr.hashValue
    }
    return h
  }
}

public final class RecordType: Type, Hashable {
  public struct Field: Hashable {
    public let name: QualifiedName
    public let type: Type

    public static func ==(lhs: Field, rhs: Field) -> Bool {
      return lhs.name == rhs.name && lhs.type === rhs.type
    }

    public var hashValue: Int {
      return name.string.hashValue ^ ObjectIdentifier(type).hashValue
    }
  }
  public let name: QualifiedName
  public let fields: [Field]

  init(name: QualifiedName, fields: [Field]) {
    self.name = name
    self.fields = fields
  }

  public static func ==(lhs: RecordType, rhs: RecordType) -> Bool {
    return lhs.name == rhs.name && lhs.fields == rhs.fields
  }

  public var hashValue: Int {
    var h = name.hashValue
    for field in fields {
      h ^= field.hashValue
    }
    return h
  }
}

public class FunctionType: Type, Hashable {
  public let arguments: [Type]
  public let returnType: Type

  init(arguments: [Type], returnType: Type) {
    self.arguments = arguments
    self.returnType = returnType
  }

  public static func ==(lhs: FunctionType, rhs: FunctionType) -> Bool {
    for (lhsArg, rhsArg) in zip(lhs.arguments, rhs.arguments) {
      guard lhsArg === rhsArg else { return false }
    }
    return lhs.returnType === rhs.returnType
  }

  public var hashValue: Int {
    var h = ObjectIdentifier(returnType).hashValue
    for arg in arguments {
      h ^= ObjectIdentifier(arg).hashValue
    }
    return h

  }
}

public class BottomType: Type, Hashable {
  public static func ==(lhs: BottomType, rhs: BottomType) -> Bool {
    return true
  }

  public var hashValue: Int {
    return 0
  }
}
