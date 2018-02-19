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

public class Continuation: Value {
  enum Kind {
    case basicBlock(parent: Continuation)
    case topLevel
    case functionHead(parent: Continuation)
  }
  let env = Environment()
  var destructors = [Destructor]()
  var parameters = [Parameter]()
  weak var module: GIRModule?

  var predList: Successor

  public var successors: AnySequence<Continuation> {
    guard let first = self.predList.successor else {
      return AnySequence<Continuation>([])
    }
    return AnySequence<Continuation>(sequence(first: first) { succ in
      return succ.predList.next?.successor
    })
  }

  /// RPO index in a forward CFG.
  var f_index_ : Int = -1
  /// RPO index in a backwards CFG.
  var b_index_ : Int = -1

  public override init(name: String, type: Type) {
    self.predList = Successor(nil)
    super.init(name: name, type: type)
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

  public override func dump() {
    print("\(self.name)(", terminator: "")
    self.parameters.forEach { param in
      param.dump()
    }
    print("):")
  }
}
