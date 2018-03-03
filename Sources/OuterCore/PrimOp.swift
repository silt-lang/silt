/// PrimOp.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// A primitive operation that has no CPS definition, yet affects the semantics
/// of a continuation.
/// These are scheduled after GraphIR generation and include operations like
/// application of functions, copying and destroying values, conditional
/// branching, and pattern matching primitives.
public class PrimOp: Value {
  /// An enum representing the kind of primitive operation this PrimOp exposes.
  public enum Code: String {
    /// A no-op operation.
    case noop

    /// An application of a function-type value.
    case apply

    /// An explicit copy operation of a value.
    case copyValue = "copy_value"

    /// A explicit destroy operation of a value.
    case destroyValue = "destroy_value"

    /// An operation that selects a matching pattern and dispatches to another
    /// continuation.
    case switchConstr = "switch_constr"

    /// An operation that represents a reference to a continuation.
    case functionRef = "function_ref"

    case dataInitSimple = "data_init_simple"
  }

  /// All the operands of this operation.
  fileprivate(set) var operands: [Operand] = []

  /// Which specific operation this PrimOp represents.
  public let opcode: Code

  /// The 'result' of this operation, or 'nil', if this operation is only for
  /// side effects.
  public var result: Value? {
    return nil
  }

  /// Initializes a PrimOp with the provided OpCode and no operands.
  ///
  /// - Parameter opcode: The opcode this PrimOp represents.
  init(opcode: Code) {
    self.opcode = opcode
    super.init(name: self.opcode.rawValue, type: BottomType.shared)
  }

  /// Adds the provided operands to this PrimOp's operand list.
  ///
  /// - Parameter ops: The operands to append to the end of the current list of
  ///                  operands.
  fileprivate func addOperands(_ ops: [Operand]) {
    self.operands.append(contentsOf: ops)
  }

  public override func dump() {
    var stream = FileHandle.standardOutput
    GIRWriter(stream: &stream).writePrimOp(self)
  }
}

public class TerminalOp: PrimOp {
  var parent: Continuation
  var successors: [Successor] {
    return []
  }
  init(opcode: Code, parent: Continuation) {
    self.parent = parent
    super.init(opcode: opcode)
  }
}

/// A primitive operation that contains no operands and has no effect.
public final class NoOp: PrimOp {
  public init() {
    super.init(opcode: .noop)
  }
}

/// A primitive operation that transfers control out of the current continuation
/// to the provided Graph IR value. The value _must_ represent a function.
public final class ApplyOp: TerminalOp {

  /// Creates a new ApplyOp to apply the given arguments to the given value.
  /// - parameter fnVal: The value to which arguments are being applied. This
  ///                    must be a value of function type.
  /// - parameter args: The values to apply to the callee. These must match the
  ///                   arity of the provided function value.
  public init(_ parent: Continuation, _ fnVal: Value, _ args: [Value]) {
    super.init(opcode: .apply, parent: parent)
    if let succ = fnVal as? FunctionRefOp {
      self.successors_.append(Successor(parent, self, succ.function))
    }
    self.addOperands(([fnVal] + args).map { arg in
      return Operand(owner: self, value: arg)
    })
  }

  private var successors_: [Successor] = []

  override var successors: [Successor] {
    return successors_
  }

  /// The value being applied to.
  var callee: Value {
    return self.operands[0].value
  }

  /// The arguments being applied to the callee.
  var arguments: ArraySlice<Operand> {
    return self.operands.dropFirst()
  }
}

public final class CopyValueOp: PrimOp {
  public init(_ value: Value) {
    super.init(opcode: .copyValue)
    self.addOperands([Operand(owner: self, value: value)])
  }

  public override var result: Value? {
    return self
  }

  var value: Operand {
    return self.operands[0]
  }
}

public final class DestroyValueOp: PrimOp {
  public init(_ value: Value) {
    super.init(opcode: .destroyValue)
    self.addOperands([Operand(owner: self, value: value)])
  }

  var value: Operand {
    return self.operands[0]
  }
}

public final class FunctionRefOp: PrimOp {
  init(continuation: Continuation) {
    super.init(opcode: .functionRef)
    self.addOperands([Operand(owner: self, value: continuation)])
  }

  var function: Continuation {
    return operands[0].value as! Continuation
  }

  public override var result: Value? {
    return self
  }
}

public final class SwitchConstrOp: TerminalOp {
  /// Initializes a SwitchConstrOp matching the constructor of the provided
  /// value with the set of pattern/apply pairs. This will dispatch to a given
  /// ApplyOp with the provided value if and only if the value was constructed
  /// with the associated constructor.
  ///
  /// - Parameters:
  ///   - value: The value you're pattern matching.
  ///   - patterns: A list of pattern/apply pairs.
  public init(_ parent: Continuation, matching value: Value,
              patterns: [(pattern: String, apply: Value)]) {
    self.patterns = patterns
    super.init(opcode: .switchConstr, parent: parent)

    self.addOperands([Operand(owner: self, value: value)])
    var ops = [Operand]()
    for (_, dest) in patterns {
      let destCont = (dest as! FunctionRefOp).function
      successors_.append(Successor(parent, self, destCont))
      ops.append(Operand(owner: self, value: dest))
    }
    self.addOperands(ops)
  }

  private var successors_: [Successor] = []

  override var successors: [Successor] {
    return successors_
  }

  public var matchedValue: Value {
    return operands[0].value
  }

  public let patterns: [(pattern: String, apply: Value)]
}

public final class DataInitSimpleOp: PrimOp {
  public let constructor: String
  public init(constructor: String) {
    self.constructor = constructor
    super.init(opcode: .dataInitSimple)
  }

  public override var result: Value? {
    return self
  }
}

public protocol PrimOpVisitor {
  func visitApplyOp(_ op: ApplyOp)
  func visitCopyValueOp(_ op: CopyValueOp)
  func visitDestroyValueOp(_ op: DestroyValueOp)
  func visitFunctionRefOp(_ op: FunctionRefOp)
  func visitSwitchConstrOp(_ op: SwitchConstrOp)
  func visitDataInitSimpleOp(_ op: DataInitSimpleOp)
}

extension PrimOpVisitor {
  public func visitPrimOp(_ code: PrimOp) {
    switch code.opcode {
    case .noop:
      fatalError()
    case .apply: self.visitApplyOp(code as! ApplyOp)
    case .copyValue: self.visitCopyValueOp(code as! CopyValueOp)
    case .destroyValue: self.visitDestroyValueOp(code as! DestroyValueOp)
    case .functionRef: self.visitFunctionRefOp(code as! FunctionRefOp)
    case .switchConstr: self.visitSwitchConstrOp(code as! SwitchConstrOp)
    case .dataInitSimple: self.visitDataInitSimpleOp(code as! DataInitSimpleOp)
    }
  }
}
