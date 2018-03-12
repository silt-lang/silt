/// Module.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public final class GIRModule {
  public let name: String

  public private(set) var continuations = [Continuation]()
  public private(set) var continuationTable = [DeclRef: Continuation]()
  public private(set) var primops = [PrimOp]()
  public private(set) var knownFunctionTypes = Set<FunctionType>()
  public private(set) var knownRecordTypes = Set<RecordType>()
  public private(set) var knownDataTypes = Set<DataType>()
  public let bottomType = BottomType.shared
  public let metadataType = TypeMetadataType()
  public let typeType = TypeType.shared

  public init(name: String = "main") {
    self.name = name
  }

  public func addContinuation(_ continuation: Continuation) {
    continuations.append(continuation)
    continuationTable[DeclRef(continuation.name, .function)] = continuation
    continuation.module = self
  }

  public func addPrimOp(_ primOp: PrimOp) {
    primops.append(primOp)
  }

  public func lookupContinuation(_ ref: DeclRef) -> Continuation? {
    return self.continuationTable[ref]
  }

  public func recordType(name: String,
                         indices: GIRType? = nil,
                         actions: (RecordType) -> Void) -> RecordType {
    let record = RecordType(name: name, indices: indices ?? TypeType.shared)
    actions(record)
    return knownRecordTypes.getOrInsert(record)
  }

  public func functionType(arguments: [GIRType],
                           returnType: GIRType) -> FunctionType {
    let function = FunctionType(arguments: arguments, returnType: returnType)
    return knownFunctionTypes.getOrInsert(function)
  }

  public func dataType(name: String,
                       indices: GIRType? = nil,
                       actions: (DataType) -> Void) -> DataType {
    let data = DataType(name: name, indices: indices ?? TypeType.shared)
    actions(data)
    return knownDataTypes.getOrInsert(data)
  }
}

extension Set {
  mutating func getOrInsert(_ value: Element) -> Element {
    if let idx = index(of: value) {
      return self[idx]
    }
    insert(value)
    return value
  }
}
