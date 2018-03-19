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
  public private(set) var parameters = [Parameter]()
  public private(set) var destroys = [DestroyValueOp]()

  weak var module: GIRModule?

  var predecessorList: Successor
  public weak var terminalOp: TerminalOp?

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

  public init(name: String) {
    self.predecessorList = Successor(nil)
    super.init(name: name, type: BottomType.shared /*to be overwritten*/)
  }

  @discardableResult
  public func appendParameter(named name: String = "", type: Value,
                              ownership: Ownership = .owned) -> Parameter {
    let param = Parameter(name: name, parent: self, index: parameters.count,
                          type: type, ownership: ownership)
    parameters.append(param)
    return param
  }

  @discardableResult
  public func setReturnParameter(type: Value) -> Parameter {
    guard let module = module else { fatalError() }

    let returnTy = module.functionType(arguments: [type],
                                       returnType: module.bottomType)
    let param = Parameter(name: "", parent: self, index: parameters.count,
                          type: returnTy, ownership: .owned)
    parameters.append(param)
    return param
  }

  public func appendDestroyable(_ value: DestroyValueOp) {
    self.destroys.append(value)
  }

  public var returnValueType: Value {
    guard let module = module else { fatalError() }

    guard let lastTy = parameters.last?.type else {
      return module.bottomType
    }
    guard let funcTy = lastTy as? FunctionType else {
      return module.bottomType
    }
    return funcTy.arguments[0]
  }

  public override var type: Value {
    get {
      guard let module = module else {
        fatalError("cannot get type of Continuation without module")
      }
      let returnTy = parameters.last?.type ?? module.bottomType
      return module.functionType(arguments: parameters.dropLast().map { $0.type },
                                 returnType: returnTy)
    }
    set { /* do nothing */ }
  }
}
