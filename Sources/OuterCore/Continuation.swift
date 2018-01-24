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

public final class Continuation: Value {
  let env = Environment()
  var call: Call?
  var destructors = [Destructor]()
  var parameters = [Parameter]()

  public override init(name: String? = nil) {
    super.init(name: env.makeUnique(name))
  }

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
