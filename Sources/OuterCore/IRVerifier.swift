/// IRVerifier.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere
import Seismography
import PrettyStackTrace

public final class IRVerifier {
  let module: GIRModule

  var currentScopedValues = Set<Value>()

  public init(module: GIRModule) {
    self.module = module
  }

  func valueIsKnown(_ value: Value) -> Bool {
    switch value {
    case let type as RecordType:
      return module.knownRecordTypes.contains(type)
    case let type as FunctionType:
      return module.knownFunctionTypes.contains(type)
    case let type as DataType:
      return module.knownDataTypes.contains(type)
    case let type as BottomType:
      return module.bottomType === type
    case let type as TypeMetadataType:
      return module.metadataType === type
    case let type as TypeType:
      return module.typeType === type
    case _ as ArchetypeType:
      return false
    case let type as SubstitutedType:
      guard valueIsKnown(type.substitutee) else { return false }
      for (arch, subst) in type.substitutions {
        guard valueIsKnown(arch) else { return false }
        guard valueIsKnown(subst) else { return false }
      }
    default: break
    }
    return true
  }

  func verifyType(_ type: Value) {
    trace("verifying GIR type") {
      guard valueIsKnown(type) else {
        fatalError("unknown type")
      }
      switch type {
      case let type as ParameterizedType:
        fatalError("""
          type \(type.name) must have all parameters substituted
          """)
      default:
        break
      }
    }
  }

  public func verify() {
    trace("verifying GIR module '\(module.name)'") {
      for continuation in module.continuations {
        _ = verify(continuation)
      }
    }
  }

  func verify(_ continuation: Continuation) -> Bool {
    return true
  }
}
