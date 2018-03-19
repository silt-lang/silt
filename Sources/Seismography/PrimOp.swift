/// PrimOp.swift
///
/// Copyright 2017-2018, The Silt Language Project.
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

    /// A simple constructor call with no parameters
    case dataInit = "data_init"

    /// An instruction that is considered 'unreachable' that will trap at
    /// runtime.
    case unreachable
  }

  /// All the operands of this operation.
  public private(set) var operands: [Operand] = []

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
}

public class TerminalOp: PrimOp {
  public var parent: Continuation

  public var successors: [Successor] {
    return []
  }
  init(opcode: Code, parent: Continuation) {
    self.parent = parent
    super.init(opcode: opcode)
    // Tie the knot
    self.parent.terminalOp = self
  }
  func overrideParent(_ parent: Continuation) {
    self.parent = parent
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

  public override var successors: [Successor] {
    return successors_
  }

  /// The value being applied to.
  public var callee: Value {
    return self.operands[0].value
  }

  /// The arguments being applied to the callee.
  public var arguments: ArraySlice<Operand> {
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

  public var value: Operand {
    return self.operands[0]
  }
}

public final class DestroyValueOp: PrimOp {
  public init(_ value: Value) {
    super.init(opcode: .destroyValue)
    self.addOperands([Operand(owner: self, value: value)])
  }

  public var value: Operand {
    return self.operands[0]
  }
}

public final class FunctionRefOp: PrimOp {
  public let function: Continuation

  public init(continuation: Continuation) {
    self.function = continuation
    super.init(opcode: .functionRef)
    self.addOperands([Operand(owner: self, value: continuation)])
  }

  public override var result: Value? {
    return self
  }

  public override var type: Value {
    return self.function.type
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
              patterns: [(pattern: String, apply: Value)], default: Value?) {
    self.patterns = patterns
    self.`default` = `default`
    super.init(opcode: .switchConstr, parent: parent)

    self.addOperands([Operand(owner: self, value: value)])
    var ops = [Operand]()
    for (_, dest) in patterns {
      ops.append(Operand(owner: self, value: dest))
      guard let destCont = (dest as? FunctionRefOp)?.function else {
        continue
      }
      successors_.append(Successor(parent, self, destCont))
    }
    if let defaultDest = `default` {
      ops.append(Operand(owner: self, value: defaultDest))
      if let destCont = (defaultDest as? FunctionRefOp)?.function {
        successors_.append(Successor(parent, self, destCont))
      }
    }
    self.addOperands(ops)
  }

  private var successors_: [Successor] = []

  public override var successors: [Successor] {
    return successors_
  }

  public var matchedValue: Value {
    return operands[0].value
  }

  public let patterns: [(pattern: String, apply: Value)]
  public let `default`: Value?
}

public final class DataInitOp: PrimOp {
  public let constructor: String
  public let dataType: Value
  public init(constructor: String, type: Value, arguments: [Value]) {
    self.constructor = constructor
    self.dataType = type
    super.init(opcode: .dataInit)
    self.addOperands(arguments.map { Operand(owner: self, value: $0) })
  }

  public override var result: Value? {
    return self
  }
}

public final class UnreachableOp: TerminalOp {
  public init(parent: Continuation) {
    super.init(opcode: .unreachable, parent: parent)
  }
}

public protocol PrimOpVisitor {
  func visitApplyOp(_ op: ApplyOp)
  func visitCopyValueOp(_ op: CopyValueOp)
  func visitDestroyValueOp(_ op: DestroyValueOp)
  func visitFunctionRefOp(_ op: FunctionRefOp)
  func visitSwitchConstrOp(_ op: SwitchConstrOp)
  func visitDataInitOp(_ op: DataInitOp)
  func visitUnreachableOp(_ op: UnreachableOp)
}

extension PrimOpVisitor {
  public func visitPrimOp(_ code: PrimOp) {
    switch code.opcode {
    case .noop:
      fatalError()
      // swiftlint:disable force_cast
    case .apply: self.visitApplyOp(code as! ApplyOp)
      // swiftlint:disable force_cast
    case .copyValue: self.visitCopyValueOp(code as! CopyValueOp)
      // swiftlint:disable force_cast
    case .destroyValue: self.visitDestroyValueOp(code as! DestroyValueOp)
      // swiftlint:disable force_cast
    case .functionRef: self.visitFunctionRefOp(code as! FunctionRefOp)
      // swiftlint:disable force_cast
    case .switchConstr: self.visitSwitchConstrOp(code as! SwitchConstrOp)
      // swiftlint:disable force_cast
    case .dataInit: self.visitDataInitOp(code as! DataInitOp)
    // swiftlint:disable force_cast
    case .unreachable: self.visitUnreachableOp(code as! UnreachableOp)
    }
  }
}
