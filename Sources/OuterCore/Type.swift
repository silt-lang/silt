/// Type.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Moho

public struct NameAndType: Hashable {
  public let name: QualifiedName
  public unowned let type: Type

  public static func ==(lhs: NameAndType, rhs: NameAndType) -> Bool {
    return lhs.name == rhs.name && lhs.type == rhs.type
  }

  public var hashValue: Int {
    return name.string.hashValue ^ ObjectIdentifier(type).hashValue
  }
}

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
  public override func equals(_ other: Type) -> Bool {
    return other is TypeMetadataType
  }
  public override var hashValue: Int {
    return 0
  }
}

public final class TypeType: Type {
  public override func equals(_ other: Type) -> Bool {
    return other is TypeType
  }
  public override var hashValue: Int {
    return 0
  }
}

public final class ArchetypeType: Type {
  unowned let type: Type
  let index: Int

  init(type: Type, index: Int) {
    self.type = type
    self.index = index
  }

  public override func equals(_ other: Type) -> Bool {
    guard let other = other as? ArchetypeType else { return false }
    return type == other.type && index == other.index
  }

  public override var hashValue: Int {
    return ObjectIdentifier(type).hashValue ^ index.hashValue ^ 0x374b2947
  }
}

public class ParameterizedType: Type {
  public struct Parameter: Hashable {
    let archetype: ArchetypeType
    let value: NameAndType

    public static func ==(lhs: Parameter, rhs: Parameter) -> Bool {
      return lhs.archetype == rhs.archetype && lhs.value == rhs.value
    }

    public var hashValue: Int {
      return archetype.hashValue ^ value.hashValue ^ 0x432fba397
    }
  }
  public private(set) var parameters = [Parameter]()

  public func addParameter(name: QualifiedName, type: Type) {
    let archetype = ArchetypeType(type: self, index: parameters.count)
    let value = NameAndType(name: name, type: type)
    parameters.append(Parameter(archetype: archetype, value: value))
  }

  private func ensureValidIndex(_ index: Int) {
    guard index < parameters.count else {
      fatalError("""
                 attempt to use archetype at index \(index) for \
                 type with \(parameters.count) archetypes
                 """)
    }
  }

  public func archetype(at index: Int) -> ArchetypeType {
    ensureValidIndex(index)
    return parameters[index].archetype
  }

  public func parameter(at index: Int) -> NameAndType {
    ensureValidIndex(index)
    return parameters[index].value
  }
}

public final class DataType: ParameterizedType {
  public typealias Constructor = NameAndType
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
    return name == other.name &&
           constructors == other.constructors &&
           parameters == other.parameters
  }

  public override var hashValue: Int {
    var h = name.hashValue
    for param in parameters {
      h ^= param.hashValue
    }
    for constr in constructors {
      h ^= constr.hashValue
    }
    return h
  }
}

public final class RecordType: ParameterizedType {
  public typealias Field = NameAndType
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
    return name == other.name &&
           fields == other.fields &&
           parameters == other.parameters
  }

  public override var hashValue: Int {
    var h = name.hashValue
    for field in fields {
      h ^= field.hashValue
    }
    for param in parameters {
      h ^= param.hashValue
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
      h ^= arg.hashValue ^ 0x2894ba9
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
