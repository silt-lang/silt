/// Continuation.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

public struct ParameterSemantics {
  var parameter: Parameter
  var mustDestroy: Bool
}

public final class Continuation: Value, GraphNode {
  public enum CallingConvention {
    /// The default calling convention for Silt functions.
    case `default`
    /// The indirect calling convention for Silt functions.
    ///
    /// When calling the function, an extra indirect return parameter is
    /// added before the return continuation parameter. The caller is required
    /// to allocate a buffer of the appropriate size and pass it in that
    /// position. The callee is then required to initialize that buffer by
    /// storing into it before the return continuation is called with the
    /// caller-provided buffer. Finally, the return continuation must be
    /// caller-controlled and call the appropriate resource destruction primop
    /// on the buffer it allocated.
    case indirectResult
  }
  public private(set) var parameters = [Parameter]()
  public private(set) var indirectReturnParameter: Parameter?
  public private(set) var cleanups = [PrimOp]()

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

  public var callingConvention: CallingConvention {
    if self.indirectReturnParameter != nil {
      return .indirectResult
    }
    return .default
  }

  public init(name: String) {
    self.predecessorList = Successor(nil)
    super.init(name: name, type: BottomType.shared /*to be overwritten*/,
               category: .address)
  }

  @discardableResult
  public func appendParameter(
    named name: String = "", type: GIRType
  ) -> Parameter {
    let param = Parameter(name: name, parent: self, index: parameters.count,
                          type: type)
    parameters.append(param)
    return param
  }

  public func appendCleanupOp(_ cleanup: PrimOp) {
    self.cleanups.append(cleanup)
  }

  @discardableResult
  public func appendIndirectReturnParameter(type: GIRType) -> Parameter {
    precondition(type.category == .address,
                 "Can only add indirect return parameter with address type")
    let param = Parameter(name: "", parent: self, index: parameters.count,
                          type: type)
    indirectReturnParameter = param
    parameters.append(param)
    return param
  }

  @discardableResult
  public func setReturnParameter(type: Value) -> Parameter {
    guard let module = module else { fatalError() }

    let returnTy = module.functionType(arguments: [type],
                                       returnType: module.bottomType)
    let param = Parameter(name: "", parent: self, index: parameters.count,
                          type: returnTy)
    parameters.append(param)
    return param
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
      let paramTys = parameters.dropLast().map { $0.type }
      return module.functionType(arguments: paramTys, returnType: returnTy)
    }
    set { /* do nothing */ }
  }
}
