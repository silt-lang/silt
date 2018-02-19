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
  let module: Module

  public init(module: Module) {
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
        verify(continuation)
      }
    }
  }

  func verifyApply(_ apply: Apply) {
    trace("verifying apply of '\(name(for: apply.callee))'") {
      guard let fnType = apply.callee.type as? FunctionType else {
        fatalError("""
          attempt to call non-function type '\(name(for: apply.callee.type))'
          """)
      }

      guard fnType.arguments.count == apply.args.count else {
        let expected = fnType.arguments.count
        let got = apply.args.count

        let qualifier = expected > got ? "few" : "many"
        let kind = apply.callee is Continuation ? "function" : "value"
        fatalError("""
          too \(qualifier) arguments to GIR \(kind) \
          '\(apply.callee.name)'; expected \(expected), got \(got)
          """)
      }
      for (arg, param) in zip(apply.args, fnType.arguments) {
        trace("verifying GIR apply argument '\(name(for: arg))'") {
          verifyType(arg.type)
          verifyType(param)
          guard arg.type === param else {
            fatalError("""
              type mismatch (expected '\(name(for: param))', \
              got '\(name(for: arg.type))'
              """)
          }
        }
      }
    }
  }

  func verify(_ continuation: Continuation) {
    let n = name(for: continuation)
    trace("verifying GIR continuation '\(n)'") {
      for parameter in continuation.parameters {
        verifyType(parameter.type)
      }
      guard let call = continuation.call else {
        fatalError("continuation '\(continuation.name)' has no call")
      }
      verifyApply(call)
    }
  }
}
