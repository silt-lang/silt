//
//  IRVerifier.swift
//  OuterCore
//
//  Created by Harlan Haskins on 1/28/18.
//

import Foundation
import Lithosphere
import PrettyStackTrace

extension Diagnostic.Message {
  static func continuationHasNoCall(
    _ continuation: Continuation) -> Diagnostic.Message {
    return .init(.error,
                 """
                 Graph IR: continuation '\(continuation.name)' has no call
                 """)
  }
  static func callingNonFunction(_ type: Type) -> Diagnostic.Message {
    return .init(.error,
                 """
                 Graph IR: attempt to call non-function type \
                 '\(name(for: type))'
                 """)
  }
  static func arityMismatch(function: Value, expected: Int,
                            got: Int) -> Diagnostic.Message {
    let qualifier = expected > got ? "few" : "many"
    let kind = function is Continuation ? "function" : "value"
    return .init(.error,
                 """
                 Graph IR: too \(qualifier) arguments to Graph IR \(kind) \
                 '\(function.name)'; expected \(expected), got \(got)
                 """)
  }
  static func typeMismatch(expected: Type, got: Type) -> Diagnostic.Message {
    return .init(.error,
                 """
                 Graph IR: type mismatch (expected '\(name(for: expected))', \
                 got '\(name(for: got))')
                 """)
  }

  static func unsubstitutedType(
    _ type: ParameterizedType) -> Diagnostic.Message {
    return .init(.error,
                 """
                 Graph IR: type \(name(for: type)) must have all parameters \
                 substituted
                 """)
  }
}

public final class IRVerifier {
  let module: Module
  let engine: DiagnosticEngine

  public init(module: Module, engine: DiagnosticEngine) {
    self.module = module
    self.engine = engine
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
      return true
    default:
      return true
    }
  }

  func verifyType(_ type: Value) -> Bool {
    return trace("verifying Graph IR type \(name(for: type))") {
      guard valueIsKnown(type) else {
        fatalError("unknown type '\(name(for: type))'")
      }
      switch type {
      case let type as ParameterizedType:
        engine.diagnose(.unsubstitutedType(type))
        return false
      default:
        break
      }
      return true
    }
  }

  @discardableResult
  public func verify() -> Bool {
    var allValid = true
    for continuation in module.continuations {
      allValid &= verify(continuation)
    }
    return allValid
  }

  func verify(_ continuation: Continuation) -> Bool {
    return trace("verifying Graph IR continuation \(continuation.name)") {
      var allValid = true
      for parameter in continuation.parameters {
        allValid &= verifyType(parameter.type)
      }
      guard let call = continuation.call else {
        engine.diagnose(.continuationHasNoCall(continuation))
        return false
      }
      guard let fnType = call.callee.type as? FunctionType else {
        engine.diagnose(.callingNonFunction(call.callee.type))
        return false
      }

      guard fnType.arguments.count == call.args.count else {
        engine.diagnose(.arityMismatch(function: call.callee,
                                       expected: fnType.arguments.count,
                                       got: call.args.count))
        return false
      }
      for (arg, param) in zip(call.args, fnType.arguments) {
        allValid &= verifyType(arg.type)
        allValid &= verifyType(param)
        guard arg.type === param else {
          engine.diagnose(.typeMismatch(expected: param, got: arg.type))
          return false
        }
      }
      return allValid
    }
  }
}

func &=(lhs: inout Bool, rhs: Bool) {
  lhs = lhs && rhs
}
