/// Continuation.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

public struct ParameterSemantics {
  var parameter: Parameter
  var mustDestroy: Bool
}

public final class Continuation: Value, Graph {
  enum Kind {
    case basicBlock(parent: Continuation)
    case topLevel
    case functionHead(parent: Continuation)
  }
  public private(set) var parameters = [Parameter]()
  public private(set) var destroys = [DestroyValueOp]()

  weak var module: GIRModule?

  var predecessorList: Successor
  public weak var terminalOp: TerminalOp?

  // FIXME: This can't possibly be right?
  public var predecessors: AnySequence<Continuation> {
    guard let first = self.predecessorList.parent else {
      return AnySequence<Continuation>([])
    }
    return AnySequence<Continuation>(sequence(first: first) { pred in
      return pred.predecessorList.parent
    })
  }

  public var successors: [Continuation] {
    guard let terminal = self.terminalOp else {
      return []
    }

    return terminal.successors.map { succ in
      return succ.successor!
    }
  }

  public override init(name: String, type: GIRType) {
    self.predecessorList = Successor(nil)
    super.init(name: name, type: type)
  }

  @discardableResult
  public func appendParameter(type: Value,
                              ownership: Ownership = .owned) -> Parameter {
    let param = Parameter(parent: self, index: parameters.count,
                          type: type, ownership: ownership)
    parameters.append(param)
    return param
  }

  public func appendDestroyable(_ value: DestroyValueOp) {
    self.destroys.append(value)
  }

  public override var type: Value {
    get {
      guard let module = module else {
        fatalError("cannot get type of Continuation without module")
      }
      return module.functionType(arguments: parameters.map { $0.type },
                                 returnType: module.bottomType)
    }
    set { /* do nothing */ }
  }
}
