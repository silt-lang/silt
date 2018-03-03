/// Type.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere

public struct NameAndType: Hashable {
  public let name: String
  public unowned let type: Type

  public static func == (lhs: NameAndType, rhs: NameAndType) -> Bool {
    return lhs.name == rhs.name && lhs.type == rhs.type
  }

  public var hashValue: Int {
    return name.hashValue ^ ObjectIdentifier(type).hashValue
  }
}

// FIXME: Temporary
public final class GIRType: Type {
  let expr: ExprSyntax
  public init(_ expr: ExprSyntax) {
    self.expr = expr
    super.init(name: "", type: TypeType.shared)
  }
}

public final class TypeMetadataType: Type {
  init() {
    super.init(name: "", type: TypeType.shared)
  }
  public override func equals(_ other: Value) -> Bool {
    return other is TypeMetadataType
  }
  public override var hashValue: Int {
    return 0
  }
}

public final class TypeType: Type {
  static let shared = TypeType()

  init() {
    let typeType =
      /// HACK: This only exists to appease the typechecker.
      unsafeBitCast(nil as TypeType?, to: TypeType.self)
    super.init(name: "", type: typeType)
  }

  public override var type: Value {
    get { return self }
    set { /* do nothing */ }
  }

  public override func equals(_ other: Value) -> Bool {
    return other is TypeType
  }

  public override var hashValue: Int {
    return 0
  }
}

public final class ArchetypeType: Type {
  unowned let parent: ParameterizedType
  let index: Int

  init(parent: ParameterizedType, index: Int) {
    self.parent = parent
    self.index = index
    super.init(name: "", type: TypeType.shared)
  }

  public override func equals(_ other: Value) -> Bool {
    guard let other = other as? ArchetypeType else { return false }
    return parent == other.parent && index == other.index
  }

  public override var hashValue: Int {
    return ObjectIdentifier(parent).hashValue ^ index.hashValue ^ 0x374b2947
  }
}

public class ParameterizedType: Type {
  public struct Parameter: Hashable {
    /*owned */let archetype: ArchetypeType
    let value: NameAndType

    public static func == (lhs: Parameter, rhs: Parameter) -> Bool {
      return lhs.archetype == rhs.archetype && lhs.value == rhs.value
    }

    public var hashValue: Int {
      return archetype.hashValue ^ value.hashValue ^ 0x432fba397
    }
  }
  public private(set) var parameters = [Parameter]()
  public private(set) var substitutions = Set<SubstitutedType>()

  init(name: String, indices: Type) {
    super.init(name: name, type: indices)
  }

  public func addParameter(name: String, type: Type) {
    let archetype = ArchetypeType(parent: self, index: parameters.count)
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

  public func substituted(_ substitutions: [Type: Type]) -> SubstitutedType {
    let subst = SubstitutedType(substitutee: self, substitutions: substitutions)
    return self.substitutions.getOrInsert(subst)
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
  public private(set) var constructors = [Constructor]()

  public func addConstructor(name: String, type: Type) {
    constructors.append(Constructor(name: name, type: type))
  }

  public override func equals(_ other: Value) -> Bool {
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

public typealias Type = Value

public final class RecordType: ParameterizedType {
  public typealias Field = NameAndType
  public private(set) var fields = [Field]()

  public func addField(name: String, type: Type) {
    fields.append(Field(name: name, type: type))
  }

  public override func equals(_ other: Value) -> Bool {
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
  public let arguments: UnownedArray<Type>
  public unowned let returnType: Type

  init(arguments: [Type], returnType: Type) {
    self.arguments = UnownedArray(values: arguments)
    self.returnType = returnType
    super.init(name: "", type: TypeType.shared)
  }

  public override func equals(_ other: Value) -> Bool {
    guard let other = other as? FunctionType else { return false }
    return returnType === other.returnType && arguments == other.arguments
  }

  public override var hashValue: Int {
    return returnType.hashValue ^ arguments.hashValue
  }
}

public final class SubstitutedType: Type {
  unowned let substitutee: ParameterizedType
  let substitutions: UnownedDictionary<Type, Type>

  init(substitutee: ParameterizedType, substitutions: [Type: Type]) {
    self.substitutee = substitutee
    self.substitutions = UnownedDictionary(substitutions)
    super.init(name: "", type: TypeType.shared)
  }

  public override func equals(_ other: Value) -> Bool {
    guard let other = other as? SubstitutedType else { return false }
    return substitutee == other.substitutee &&
           substitutions == other.substitutions
  }

  public override var hashValue: Int {
    return substitutee.hashValue ^ substitutions.hashValue
  }
}

public final class BottomType: Type {
  public static let shared = BottomType()

  init() {
    super.init(name: "", type: TypeType.shared)
  }

  public override var type: Value {
    get { return self }
    set { /* do nothing */ }
  }

  public override func equals(_ other: Value) -> Bool {
    return other is BottomType
  }

  public override var hashValue: Int {
    return 0
  }
}
