/// IRGenType.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import Seismography
import LLVM
import PrettyStackTrace

struct LoweredStructure {
  let typeName: String
  let fields: [LoweredDataType]
}

struct TaggedUnionType {
  /// The type of the tag bits of this struct.
  /// If this is `nil`, this struct doesn't need tags because it only
  /// has one constructor.
  var tagType: IntType?
  var payloadTypes: [Int: LoweredStructure]

  var payloadIndex: Int32 {
    return tagType == nil ? 0 : 1
  }
}

enum LoweredDataType {
  /// A type with no constructors, e.g. ⏊
  case void

  /// A simple tagged type with no parameterized values.
  case tagged(String, IntType)

  /// A tagged union which contains a type-erased container of bits equal to
  /// the size of the largest payload.
  case taggedUnion(String, TaggedUnionType)
}

struct IRGenType {
  weak var igm: IRGenModule!

  let type: GIRType
  init(type: GIRType, irGenModule: IRGenModule) {
    self.type = type
    self.igm = irGenModule
  }

  func lower() -> LoweredDataType {
    guard let data = type as? DataType else {
      fatalError("only know how to emit data types")
    }
    let name = igm.mangler.mangle(data, isTopLevel: true)

    let largestValueNeeded = data.constructors.count - 1
    let numBitsRequired =
      largestValueNeeded.bitWidth - largestValueNeeded.leadingZeroBitCount

    let tagType = numBitsRequired == 0 ? nil : IntType(width: numBitsRequired)

    let hasParameterizedConstructors =
      data.constructors.contains { $0.payload != nil }

    // Simple case: No payloads, all constructors are simple.
    if data.parameters.isEmpty && !hasParameterizedConstructors {
      guard let tagType = tagType else { return .void }
      return .tagged(name, tagType)
    }

    // Otherwise, build a registry of payload types.
    // This maps tag bits to the corresponding struct type in the union.
    var tags = [Int: LoweredStructure]()
    for (idx, constructor) in data.constructors.enumerated() {
      guard let payloadType = constructor.payload else {
        continue
      }

      let typeName =
        igm.mangler.mangle(constructor, isTopLevel: true) + ".payload"

      // Turn the function constructors into a flattened list of members.
      let fields = payloadType.elements.map { type in
        return IRGenType(type: type, irGenModule: igm).lower()
      }

      tags[idx] = LoweredStructure(typeName: typeName, fields: fields)
    }
    return .taggedUnion(
      name,
      TaggedUnionType(tagType: tagType, payloadTypes: tags))
  }

  func emit(_ structure: LoweredStructure) -> StructType {
    if let ty = igm.module.type(named: structure.typeName) {
      // swiftlint:disable force_cast
      return ty as! StructType
    }
    return igm.B.createStruct(
      name: structure.typeName,
      types: structure.fields.map(emit),
      isPacked: true
    )
  }

  func emit(_ lowered: LoweredDataType) -> IRType {
    return trace("emitting LLVM IR for GIR type \(type.name)") {
      switch lowered {
      case let .tagged(_, type): return type
      case .void:
        return VoidType()
      case let .taggedUnion(name, union):
        if let type = igm.module.type(named: name) { return type }
        let layout = self.igm.module.dataLayout
        let fieldTys = union.payloadTypes.values.map(emit)
        let maxPayloadSize = fieldTys.map(layout.abiSize).max()!
        let byteVector = ArrayType(
          elementType: IntType.int8,
          count: maxPayloadSize
        )

        var types: [IRType] = [byteVector]
        if let tag = union.tagType {
          types.insert(tag, at: 0)
        }
        return igm.B.createStruct(
          name: name,
          types: types,
          isPacked: true
        )
      }
    }
  }

  func extractAddressOfPayload(atTag tag: Int, from value: IRValue) -> IRValue {
    let lowered = lower()
    guard case let .taggedUnion(_, unionTy) = lowered else {
      fatalError("cannot extract value from type \(lowered) with no payload")
    }
    guard let payloadType = unionTy.payloadTypes[tag] else {
      fatalError("no payload on constructor \(tag)")
    }
    let irType = emit(payloadType)
    let gep = igm.B.buildGEP(value, indices: [0, unionTy.payloadIndex])
    return igm.B.buildBitCast(gep, type: PointerType(pointee: irType))
  }

  func extractPayload(atTag tag: Int, from value: IRValue) -> IRValue {
    return igm.B.buildLoad(extractAddressOfPayload(atTag: tag, from: value))
  }

  func initialize(tag: Int) -> IRValue {
    let type = lower()
    switch type {
    case let .tagged(_, intType):
      return intType.constant(tag)
    case .void:
      return VoidType().null()
    case let .taggedUnion(_, unionTy):
      // swiftlint:disable force_cast
      let structTy = emit(type) as! StructType
      var value = structTy.null()
      if let tagType = unionTy.tagType {
        value = igm.B.buildInsertValue(
          aggregate: value,
          element: tagType.constant(tag),
          index: 0
        )
      }
      return value
    }
  }

}
