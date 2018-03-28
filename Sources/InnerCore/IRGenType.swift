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

struct IRGenType {
  weak var igm: IRGenModule!

  let type: GIRType
  init(type: GIRType, irGenModule: IRGenModule) {
    self.type = type
    self.igm = irGenModule
  }

  func emit() -> IRType {
    return trace("emitting LLVM IR for GIR type \(type.name)") {
      guard let data = type as? DataType else {
        fatalError("only know how to emit data types")
      }
      guard data.parameters.isEmpty else {
        fatalError("only know how to emit non-parameterized types")
      }
      let hasParameterizedConstructors =
        data.constructors.contains { $0.type is Seismography.FunctionType }
      guard !hasParameterizedConstructors else {
        fatalError("cannot handle parameterized constructors")
      }

      if data.constructors.isEmpty {
        return VoidType()
      }

      let numBitsRequired = Int(log2(Double(data.constructors.count))) + 1
      return IntType(width: numBitsRequired)
    }
  }
}
