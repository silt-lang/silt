/// Module.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Moho

public final class GIRModule {
  public let name: String

  public let context: GIRContext = GIRContext()
  public private(set) var continuations = [Continuation]()
  public private(set) var continuationTable = [DeclRef: Continuation]()
  public private(set) var primops = [PrimOp]()
  public private(set) var knownFunctionTypes = Set<FunctionType>()
  public private(set) var knownRecordTypes = Set<RecordType>()
  public private(set) var knownDataTypes = Set<DataType>()
  public let bottomType = BottomType.shared
  public let metadataType = TypeMetadataType()
  public let typeType = TypeType.shared
  public let typeConverter: TypeConverter
  private weak var parentModule: GIRModule?

  public init(name: String = "main", parent: GIRModule?, tc: TypeConverter) {
    self.name = name
    self.parentModule = parent
    self.typeConverter = tc
    self.typeConverter.module = self
  }

  public func addContinuation(_ continuation: Continuation) {
    continuations.append(continuation)
    continuationTable[keyForContinuation(continuation)] = continuation
    continuation.module = self
  }

  public func removeContinuation(_ continuation: Continuation) {
    continuations.removeAll(where: { $0 == continuation })
    continuationTable[keyForContinuation(continuation)] = nil
    continuation.module = nil
  }

  public func addPrimOp(_ primOp: PrimOp) {
    primops.append(primOp)
  }

  public func lookupContinuation(_ ref: DeclRef) -> Continuation? {
    return self.continuationTable[ref]
  }

  public func functionType(arguments: [GIRType],
                           returnType: GIRType) -> FunctionType {
    let function = FunctionType(arguments: arguments, returnType: returnType)
    return knownFunctionTypes.getOrInsert(function)
  }

  public func dataType(name: QualifiedName,
                       module: GIRModule? = nil,
                       indices: GIRType?,
                       category: Value.Category) -> DataType {
    var hasher = Hasher()
    name.hash(into: &hasher)
    if let module = module {
      Unmanaged.passUnretained(module).toOpaque().hash(into: &hasher)
    }
    let id = hasher.finalize()
    guard let existing = self.context.dataTypes[id] else {
      let data = DataType(name: name,
                          module: module,
                          indices: indices ?? TypeType.shared,
                          constructors: [],
                          category: category)
      self.context.dataTypes[id] = .init(data)
      _ = self.knownDataTypes.getOrInsert(data)
      return data
    }
    return existing.value
  }

  public func natType(name: QualifiedName,
                      zero: String,
                      succ: String,
                      module: GIRModule? = nil,
                      category: Value.Category) -> DataType {
    var hasher = Hasher()
    name.hash(into: &hasher)
    if let module = module {
      Unmanaged.passUnretained(module).toOpaque().hash(into: &hasher)
    }
    2.hash(into: &hasher)
    let id = hasher.finalize()
    guard let existing = self.context.dataTypes[id] else {
      let data = DataType(name: name,
                          module: module,
                          indices: TypeType.shared,
                          constructors: [],
                          category: category)
      let payloadTy = TupleType(elements: [ data ], category: .object)
      data.addConstructors([
        (name: zero, payload: nil),
        (name: succ, payload: payloadTy),
      ])
      self.context.dataTypes[id] = .init(data)
      _ = self.knownDataTypes.getOrInsert(data)
      return data
    }
    return existing.value
  }
}

extension Set {
  mutating func getOrInsert(_ value: Element) -> Element {
    if let idx = firstIndex(of: value) {
      return self[idx]
    }
    insert(value)
    return value
  }
}

extension GIRModule: DeclarationContext {
  public var contextKind: DeclarationContextKind {
    return .module
  }

  public var parent: DeclarationContext? {
    return self.parentModule
  }
}

private func keyForContinuation(_ cont: Continuation) -> DeclRef {
  let fullName = cont.name.string + (cont.bblikeSuffix ?? "")
  return DeclRef(fullName, .function)
}
