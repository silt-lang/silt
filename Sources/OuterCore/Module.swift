/// Module.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Moho

public final class Module {
  public let name: String

  public private(set) var continuations = [Continuation]()
  public private(set) var knownFunctionTypes = Set<FunctionType>()
  public private(set) var knownRecordTypes = Set<RecordType>()
  public private(set) var knownMetadataTypes = Set<TypeMetadataType>()
  public private(set) var knownDataTypes = Set<DataType>()
  public let bottomType = BottomType()

  public init(name: String = "main") {
    self.name = name
  }

  public func addContinuation(_ continuation: Continuation) {
    continuations.append(continuation)
  }

  public func recordType(name: QualifiedName,
                         fields: [RecordType.Field]) -> RecordType {
    let record = RecordType(name: name, fields: fields)
    return knownRecordTypes.getOrInsert(record)
  }

  public func functionType(arguments: [Type], returnType: Type) -> FunctionType {
    let function = FunctionType(arguments: arguments, returnType: returnType)
    return knownFunctionTypes.getOrInsert(function)
  }

  public func metadataType(type: Type) -> TypeMetadataType {
    let meta = TypeMetadataType(type: type)
    return knownMetadataTypes.getOrInsert(meta)
  }

  public func dataType(name: QualifiedName,
                       constructors: [DataType.Constructor]) -> DataType {
    let data = DataType(name: name, constructors: constructors)
    return knownDataTypes.getOrInsert(data)
  }
}

extension Set {
  mutating func getOrInsert(_ value: Element) -> Element {
    if let idx = index(of: value) { return self[idx] }
    insert(value)
    return value
  }
}
