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

public struct ParameterSemantics {
  var parameter: Parameter
  var mustDestroy: Bool
}

public final class Continuation: Value {
  enum Kind {
    case basicBlock(parent: Continuation)
    case topLevel
    case functionHead(parent: Continuation)
  }
  let env = Environment()
  var call: Apply?
  var destructors = [Destructor]()
  var parameters = [Parameter]()
  weak var module: Module?

  var predecessors = OrderedSet<Continuation>()
  var successors = OrderedSet<Continuation>()

  init(name: String) {
    super.init(name: name, type: /* will be overwritten */BottomType.shared)
  }

  @discardableResult
  public func appendParameter(type: Value, ownership: Ownership = .owned,
                              name: String? = nil) -> Parameter {
    let param = Parameter(parent: self, index: parameters.count,
                          type: type, ownership: ownership,
                          name: env.makeUnique(name))
    parameters.append(param)
    return param
  }

  public func setCall(_ callee: Value, _ args: [Value]) {
    self.call = Apply(callee: callee, args: args)
  }

  override var type: Value {
    get {
      guard let module = module else {
        fatalError("cannot get type of Continuation without module")
      }
      return module.functionType(arguments: parameters.map { $0.type },
                                 returnType: module.bottomType)
    }
    set { /* do nothing */ }
  }

  func computeParameterSemantics() -> [ParameterSemantics] {
    var semantics = [ParameterSemantics]()
    for param in parameters {
      var semantic = ParameterSemantics(parameter: param, mustDestroy: false)

      // Start by assuming all owned parameters must be destroyed.
      if param.isOwned {
        semantic.mustDestroy = true
      }

      // If we have a call, and we're passing this parameter to the call,
      // then determine if we're transferring ownership.
      if let call = call, let index = call.args.index(of: param) {
        // If we're passing this parameter to a continuation which will own
        // it, then remove the destructor. We are transferring ownership.

        /// TODO: Handle non-Continuations being called.
        if let cont = call.callee as? Continuation,
           // out-of-bounds arguments will be caught by the verifier, just don't
           // crash while computing this.
           cont.parameters.indices.contains(index),
           cont.parameters[index].isOwned {
          semantic.mustDestroy = false
        }
      }

      semantics.append(semantic)
    }
    return semantics
  }
}

public class Apply: Value {
  public let callee: Value
  public let args: [Value]

  init(callee: Value, args: [Value]) {
    self.callee = callee
    self.args = args
    super.init(name: "", type: /* will be overwritten */BottomType())
  }

  override var type: Value {
    get {
      guard let fnTy = callee.type as? FunctionType else {
        return BottomType()
      }
      return fnTy.returnType
    }
    set { /* do nothing */ }
  }
}
