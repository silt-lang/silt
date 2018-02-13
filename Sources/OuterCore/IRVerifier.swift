//
//  IRVerifier.swift
//  OuterCore
//
//  Created by Harlan Haskins on 1/28/18.
//

import Foundation
import Lithosphere

extension Diagnostic.Message {
  static func unknownType(_ type: Type) -> Diagnostic.Message {
    return .init(.error, "Graph IR: unknown type '\(name(for: type))'")
  }
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
}

public final class IRVerifier {
  let module: Module
  let engine: DiagnosticEngine

  public init(module: Module, engine: DiagnosticEngine) {
    self.module = module
    self.engine = engine
  }

  func typeIsKnown(_ type: Type) -> Bool {
    switch type {
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
      return typeIsKnown(type.type)
    case let type as SubstitutedType:
      guard typeIsKnown(type.type) else { return false }
      for (arch, subst) in type.substitutions {
        guard typeIsKnown(arch) else { return false }
        guard typeIsKnown(subst) else { return false }
      }
      return true
    default:
      return false
    }
  }

  func ensureKnown(_ type: Type) -> Bool {
    guard typeIsKnown(type) else {
      engine.diagnose(.unknownType(type))
      return false
    }
    return true
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
    var allValid = true
    for parameter in continuation.parameters {
      allValid &= ensureKnown(parameter.type)
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
      allValid &= ensureKnown(arg.type)
      allValid &= ensureKnown(param)
      guard arg.type === param else {
        engine.diagnose(.typeMismatch(expected: param, got: arg.type))
        return false
      }
    }
    return allValid
  }
}

func &=(lhs: inout Bool, rhs: Bool) {
  lhs = lhs && rhs
}
