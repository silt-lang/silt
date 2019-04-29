/// Type.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho
import Mantle

public typealias GIRType = Value

public struct NameAndType: Hashable {
  public let name: QualifiedName
  public unowned let type: GIRType

  public static func == (lhs: NameAndType, rhs: NameAndType) -> Bool {
    return lhs.name == rhs.name && lhs.type === rhs.type
  }

  public func hash(into hasher: inout Hasher) {
    self.name.hash(into: &hasher)
    ObjectIdentifier(type).hash(into: &hasher)
  }
}

public protocol TypeVisitor {
  func visitGIRExprType(_ type: GIRExprType)
  func visitTypeMetadataType(_ type: TypeMetadataType)
  func visitTypeType(_ type: TypeType)
  func visitArchetypeType(_ type: ArchetypeType)
  func visitParameterizedType(_ type: ParameterizedType)
  func visitTupleType(_ type: TupleType)
  func visitDataType(_ type: DataType)
  func visitRecordType(_ type: RecordType)
  func visitFunctionType(_ type: FunctionType)
  func visitSubstitutedType(_ type: SubstitutedType)
  func visitBoxType(_ type: BoxType)
  func visitBottomType(_ type: BottomType)
}

extension TypeVisitor {
  public func visitType(_ value: Value) {
    switch value {
    case let type as DataType:
      return self.visitDataType(type)
    case let type as RecordType:
      return self.visitRecordType(type)
    case let type as ArchetypeType:
      return self.visitArchetypeType(type)
    case let type as SubstitutedType:
      return self.visitSubstitutedType(type)
    case let type as FunctionType:
      return self.visitFunctionType(type)
    case let type as TypeMetadataType:
      return self.visitTypeMetadataType(type)
    case let type as TypeType:
      return self.visitTypeType(type)
    case let type as BottomType:
      return self.visitBottomType(type)
    case let type as GIRExprType:
      return self.visitGIRExprType(type)
    case let type as TupleType:
      return self.visitTupleType(type)
    case let type as BoxType:
      return self.visitBoxType(type)
    default:
      fatalError("attempt to serialize unknown value \(value)")
    }
  }
}

// FIXME: Temporary
public final class GIRExprType: GIRType {
  public let expr: ExprSyntax
  public init(_ expr: ExprSyntax) {
    self.expr = expr
    super.init(type: TypeType.shared, category: .object)
  }
}

public final class TypeMetadataType: GIRType {
  init() {
    super.init(type: TypeType.shared, category: .address)
  }
  public override func equals(_ other: Value) -> Bool {
    return other is TypeMetadataType
  }

  public override func hash(into hasher: inout Hasher) {}

  public override func mangle<M: Mangler>(into mangler: inout M) {
    fatalError("TODO: mangle me!")
  }
}

public final class TypeType: GIRType {
  static let shared = TypeType()

  init() {
    let typeType =
      /// HACK: This only exists to appease the typechecker.
      unsafeBitCast(nil as TypeType?, to: TypeType.self)
    super.init(type: typeType, category: .address)
  }

  public override var type: Value {
    return self
  }

  public override func equals(_ other: Value) -> Bool {
    return other is TypeType
  }

  public override func hash(into hasher: inout Hasher) {}

  public override func mangle<M: Mangler>(into mangler: inout M) {
    mangler.append("T")
  }
}

public final class ArchetypeType: Value {
  public let index: Int

  public init(index: Int) {
    self.index = index
    super.init(type: TypeType.shared, category: .address)
  }

  public override func equals(_ other: Value) -> Bool {
    guard let other = other as? ArchetypeType else { return false }
    return index == other.index
  }

  public override func hash(into hasher: inout Hasher) {
    index.hash(into: &hasher)
  }

  public override func mangle<M: Mangler>(into mangler: inout M) {
    // fatalError("TODO: mangle me!")
  }
}

public class ParameterizedType: NominalValue {
  public struct Parameter: Hashable {
    public /*owned */let archetype: ArchetypeType
    let value: NameAndType

    public static func == (lhs: Parameter, rhs: Parameter) -> Bool {
      return lhs.archetype == rhs.archetype && lhs.value == rhs.value
    }

    public func hash(into hasher: inout Hasher) {
      self.archetype.hash(into: &hasher)
      self.value.hash(into: &hasher)
    }
  }
  public private(set) var parameters = [Parameter]()
  public private(set) var substitutions = Set<SubstitutedType>()

  init(name: QualifiedName, indices: GIRType, category: Value.Category) {
    super.init(name: name, type: indices, category: category)
  }

  public func addParameter(name: QualifiedName, type: GIRType) {
    let archetype = ArchetypeType(index: parameters.count)
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

  public func substituted(
    _ substitutions: [(GIRType, GIRType)]) -> SubstitutedType {
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

  public override func mangle<M: Mangler>(into mangler: inout M) {
    fatalError("TODO: mangle me!")
  }
}

public final class TupleType: Value {
  public let elements: [GIRType]

  init(elements: [GIRType], category: Value.Category) {
    self.elements = elements
    super.init(type: TypeType.shared, category: category)
  }

  public override func equals(_ other: Value) -> Bool {
    guard let other = other as? TupleType else { return false }
    return elements == other.elements
  }

  public override func hash(into hasher: inout Hasher) {
    for element in self.elements {
      element.hash(into: &hasher)
    }
  }

  public override func mangle<M: Mangler>(into mangler: inout M) {
    self.elements.mangle(into: &mangler)
  }
}

public final class DataType: ParameterizedType {
  public typealias Constructor = (name: String, payload: GIRType?)
  public private(set) var constructors = [Constructor]()
  public private(set) weak var module: GIRModule?

  init(name: QualifiedName, module: GIRModule?,
       indices: GIRType, constructors: [Constructor],
       category: Value.Category) {
    self.module = module
    self.constructors = constructors
    super.init(name: name, indices: indices, category: category)
  }

  public override func equals(_ other: Value) -> Bool {
    guard let other = other as? DataType else { return false }
    return self === other
  }

  public override func hash(into hasher: inout Hasher) {
    name.hash(into: &hasher)
    for param in parameters {
      param.hash(into: &hasher)
    }
    for constr in constructors {
      constr.0.hash(into: &hasher)
    }
  }

  public func addConstructors(_ cs: [Constructor]) {
    self.constructors.append(contentsOf: cs)
  }

  public override func mangle<M: Mangler>(into mangler: inout M) {
    self.module?.mangle(into: &mangler)
    Identifier(self.baseName).mangle(into: &mangler)
    mangler.append("D")
  }
}

public final class RecordType: ParameterizedType {
  public typealias Field = NameAndType
  public private(set) var fields = [Field]()

  public func addField(name: QualifiedName, type: GIRType) {
    fields.append(Field(name: name, type: type))
  }

  public override func equals(_ other: Value) -> Bool {
    guard let other = other as? RecordType else { return false }
    return name == other.name &&
           fields == other.fields &&
           parameters == other.parameters
  }

  public override func hash(into hasher: inout Hasher) {
    name.hash(into: &hasher)

    for field in fields {
      field.hash(into: &hasher)
    }
    for param in parameters {
      param.hash(into: &hasher)
    }
  }

  public override func mangle<M: Mangler>(into mangler: inout M) {
    fatalError("TODO: mangle me!")
  }
}

public final class FunctionType: GIRType {
  public let arguments: UnownedArray<GIRType>
  // FIXME: This is always a function type for continuations.
  public unowned let returnType: GIRType

  init(arguments: [GIRType], returnType: GIRType) {
    self.arguments = UnownedArray(values: arguments)
    self.returnType = returnType
    super.init(type: TypeType.shared, category: .object)
  }

  public override func equals(_ other: Value) -> Bool {
    guard let other = other as? FunctionType else { return false }
    return returnType === other.returnType && arguments == other.arguments
  }

  public override func hash(into hasher: inout Hasher) {
    returnType.hash(into: &hasher)
    arguments.hash(into: &hasher)
  }

  public override func mangle<M: Mangler>(into mangler: inout M) {
    self.returnType.mangle(into: &mangler)
    self.arguments.mangle(into: &mangler)
  }
}

public final class SubstitutedType: GIRType {
  public unowned let substitutee: ParameterizedType
  public let substitutions: [(GIRType, GIRType)]

  init(substitutee: ParameterizedType, substitutions: [(GIRType, GIRType)]) {
    self.substitutee = substitutee
    self.substitutions = substitutions
    super.init(type: TypeType.shared, category: substitutee.category)
  }

  public override func equals(_ other: Value) -> Bool {
    guard let other = other as? SubstitutedType else { return false }
    return substitutee == other.substitutee &&
           zip(substitutions, other.substitutions).allSatisfy({
            $0.0.0 == $0.1.0 && $0.1.0 == $0.1.1
           })
  }

  public override func hash(into hasher: inout Hasher) {
    substitutee.hash(into: &hasher)
    for (val1, val2) in substitutions {
      val1.hash(into: &hasher)
      val2.hash(into: &hasher)
    }
  }

  public override func mangle<M: Mangler>(into mangler: inout M) {
    self.substitutions.map({ $1 }).mangle(into: &mangler)
    self.substitutee.mangle(into: &mangler)
    mangler.append("G")
  }
}

public final class BoxType: GIRType {
  public let underlyingType: GIRType

  init(_ type: GIRType) {
    self.underlyingType = type
    super.init(type: TypeType.shared, category: .object)
  }

  public override func equals(_ other: Value) -> Bool {
    guard let other = other as? BoxType else { return false }
    return self.underlyingType.equals(other.underlyingType)
  }

  public override func hash(into hasher: inout Hasher) {
    return self.underlyingType.hash(into: &hasher)
  }

  public override func mangle<M: Mangler>(into mangler: inout M) {
    fatalError("TODO: mangle me!")
  }
}

public final class BottomType: GIRType {
  public static let shared = BottomType()

  init() {
    super.init(type: TypeType.shared, category: .object)
  }

  public override var type: Value {
    return self
  }

  public override func equals(_ other: Value) -> Bool {
    return other is BottomType
  }

  public override func hash(into hasher: inout Hasher) {}

  public override func mangle<M: Mangler>(into mangler: inout M) {
    mangler.append("B")
  }
}
