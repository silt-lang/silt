/// Continuation.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Basic

public final class Environment {
  var uniqueNamePool = 0
  var counter = [String: Int]()

  func makeUnique(_ string: String?) -> String {
    guard let string = string else {
      defer { uniqueNamePool += 1 }
      return "\(uniqueNamePool)"
    }
    let existingCount = counter[string, default: 0]
    counter[string] = existingCount + 1
    if existingCount == 0 {
      return string
    } else {
      return makeUnique("\(string).\(existingCount)")
    }
  }
}

public class Intrinsic: Value {
  public enum Kind: String {
    case match
    case branch
    case conditionalBranch
  }
  let kind: Kind

  init(kind: Kind) {
    self.kind = kind
    super.init(name: kind.rawValue)
  }
}

public final class Continuation: Value {
  enum Kind {
    case basicBlock(parent: Continuation)
    case topLevel
    case functionHead(parent: Continuation)
  }
  let env = Environment()
  var call: Call?
  var destructors = [Destructor]()
  var parameters = [Parameter]()

  var predecessors = OrderedSet<Continuation>()
  var successors = OrderedSet<Continuation>()

  @discardableResult
  public func appendParameter(type: Type, name: String? = nil) -> Parameter {
    let param = Parameter(parent: self, index: parameters.count,
                          type: type, name: env.makeUnique(name))
    parameters.append(param)
    return param
  }

  public func setCall(_ callee: Value, _ args: [Value]) {
    self.call = Call(callee: callee, args: args)
  }
}

public struct Call {
  public let callee: Value
  public let args: [Value]
}
