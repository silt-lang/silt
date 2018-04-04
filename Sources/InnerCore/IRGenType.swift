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

enum LoweredDataType {
  case void
  case simpleData(numberOfBits: Int)
  case complexData(tagBits: Int,
                   parameters: [DataType.Parameter],
                   constructors: [DataType.Constructor])
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
    if data.constructors.isEmpty {
      return .void
    }

    let largestValueNeeded = data.constructors.count - 1
    let numBitsRequired = largestValueNeeded.bitWidth - largestValueNeeded.leadingZeroBitCount

    let hasParameterizedConstructors =
      data.constructors.contains { $0.type is Seismography.FunctionType }
    if data.parameters.isEmpty && !hasParameterizedConstructors {
      return .simpleData(numberOfBits: numBitsRequired)
    }

    return .complexData(tagBits: numBitsRequired,
                        parameters: data.parameters,
                        constructors: data.constructors)
  }

  func emit() -> IRType {
    return trace("emitting LLVM IR for GIR type \(type.name)") {
      switch lower() {
      case let .simpleData(numberOfBits):
        return IntType(width: numberOfBits)
      case .void:
        return VoidType()
      case .complexData(_, _, _):
        fatalError("complex data types are unsupported")
      }
    }
  }

  func initialize(tag: Int) -> IRValue {
    switch lower() {
    case let .simpleData(numberOfBits):
      return IntType(width: numberOfBits).constant(tag)
    case .void:
      return VoidType().null()
    case .complexData(_, _, _):
      fatalError("complex data types are unsupported")
    }
  }

}
