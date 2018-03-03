//
//  IRVerifier.swift
//  OuterCore
//
//  Created by Harlan Haskins on 1/28/18.
//

import Foundation
import Lithosphere
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
    case let type as ArchetypeType:
      return valueIsKnown(type.parent)
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
    trace("verifying GIR type '\(name(for: type))'") {
      guard valueIsKnown(type) else {
        fatalError("unknown type '\(name(for: type))'")
      }
      switch type {
      case let type as ParameterizedType:
        fatalError("""
          type \(name(for: type)) must have all parameters substituted
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
