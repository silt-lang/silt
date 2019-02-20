/// Continuation.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Moho

public struct ParameterSemantics {
  var parameter: Parameter
  var mustDestroy: Bool
}

public final class Continuation: NominalValue, GraphNode {
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
  public let bblikeSuffix: String?

  weak var module: GIRModule?

  var predecessorList: Successor
  public weak var terminalOp: TerminalOp?

  public var predecessors: AnySequence<Continuation> {
    return AnySequence { () in
      return PredecessorIterator(self.predecessorList)
    }
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

  public init(name: QualifiedName, suffix: String? = nil) {
    self.predecessorList = Successor(nil)
    self.bblikeSuffix = suffix
    super.init(name: name, type: BottomType.shared /*to be overwritten*/,
               category: .address)
  }

  @discardableResult
  public func appendParameter(type: GIRType) -> Parameter {
    let param = Parameter(parent: self, index: parameters.count, type: type)
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
    let param = Parameter(parent: self, index: parameters.count, type: type)
    indirectReturnParameter = param
    parameters.append(param)
    return param
  }

  @discardableResult
  public func setReturnParameter(type: Value) -> Parameter {
    guard let module = module else { fatalError() }
    let returnTy = module.functionType(arguments: [type],
                                       returnType: module.bottomType)
    let param = Parameter(parent: self, index: parameters.count,
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

  public var formalParameters: [Parameter] {
    // FIXME: This is a bloody awful heuristic for this.
    guard self.bblikeSuffix == nil else {
      return self.parameters
    }
    return Array(self.parameters.dropLast())
  }

  public override var type: Value {
    guard let module = module else {
      fatalError("cannot get type of Continuation without module")
    }
    let returnTy = parameters.last?.type ?? module.bottomType
    let paramTys = parameters.dropLast().map { $0.type }
    return module.functionType(arguments: paramTys, returnType: returnTy)
  }

  public override func mangle<M: Mangler>(into mangler: inout M) {
    self.module?.mangle(into: &mangler)
    Identifier(self.baseName + (self.bblikeSuffix ?? "")).mangle(into: &mangler)
    guard let contTy = self.type as? FunctionType else {
      fatalError()
    }
    self.returnValueType.mangle(into: &mangler)
    contTy.arguments.mangle(into: &mangler)
    mangler.append("F")
  }
}

extension Continuation: DeclarationContext {
  public var contextKind: DeclarationContextKind {
    return .continuation
  }

  public var parent: DeclarationContext? {
    return self.module
  }
}
