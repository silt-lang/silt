/// PrimOp.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Moho

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

    /// Stack allocation.
    case alloca

    /// Stack deallocation.
    case dealloca

    /// An application of a function-type value.
    case apply

    /// An explicit copy operation of a value.
    case copyValue = "copy_value"

    /// A explicit destroy operation of a value.
    case destroyValue = "destroy_value"

    /// When the type of the source value is loadable, loads the source
    /// value and stores a copy of it to memory at the given address.
    ///
    /// When the type of the source value is address-only, copies the address
    /// from the source value to the address at the destination value.
    ///
    /// Returns the destination's memory.
    case copyAddress = "copy_address"

    /// Destroys the value pointed to by the given address but does not
    /// deallocate the memory at that address.  The appropriate memory
    /// deallocation instruction should be scheduled instead.
    case destroyAddress = "destroy_address"

    /// An operation that selects a matching pattern and dispatches to another
    /// continuation.
    case switchConstr = "switch_constr"

    /// An operation that represents a reference to a continuation.
    case functionRef = "function_ref"

    /// A data constructor call with all parameters provided at +1.
    case dataInit = "data_init"

    /// Heap-allocate a box large enough to hold a given type.
    case allocBox = "alloc_box"

    /// Deallocate a heap-allocated box.
    case deallocBox = "dealloc_box"

    /// Retrieve the address of the value inside a box.
    case projectBox = "project_box"

    /// Load the value stored at an address.
    case load = "load"

    /// Store a given value to memory allocated by a given box and returns the
    /// newly-updated box value.
    case store = "store"

    case tuple

    case tupleElementAddress = "tuple_element_address"

    case thicken

    case forceEffects = "force_effects"

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
  init(opcode: Code, type: GIRType, category: Value.Category) {
    self.opcode = opcode
    super.init(type: type, category: category)
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
    super.init(opcode: opcode, type: BottomType.shared, category: .object)
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
    super.init(opcode: .noop, type: BottomType.shared, category: .object)
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

public final class AllocaOp: PrimOp {
  public init(_ type: GIRType) {
    super.init(opcode: .alloca, type: type, category: .address)
    self.addOperands([Operand(owner: self, value: type)])
  }

  public override var result: Value? {
    return self
  }

  public var addressType: GIRType {
    return self.operands[0].value
  }
}

public final class DeallocaOp: PrimOp {
  public init(_ value: GIRType) {
    super.init(opcode: .dealloca, type: BottomType.shared, category: .object)
    self.addOperands([Operand(owner: self, value: value)])
  }

  public var addressValue: Value {
    return self.operands[0].value
  }
}

public final class CopyValueOp: PrimOp {
  public init(_ value: Value) {
    super.init(opcode: .copyValue,
               type: value.type, category: value.type.category)
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
    super.init(opcode: .destroyValue,
               type: BottomType.shared, category: .object)
    self.addOperands([Operand(owner: self, value: value)])
  }

  public var value: Operand {
    return self.operands[0]
  }
}

public final class CopyAddressOp: PrimOp {
  public init(_ value: Value, to address: Value) {
    super.init(opcode: .copyAddress,
               type: address.type, category: value.type.category)
    self.addOperands([Operand(owner: self, value: value)])
    self.addOperands([Operand(owner: self, value: address)])
  }

  public override var result: Value? {
    return self
  }

  public var value: Value {
    return self.operands[0].value
  }

  public var address: Value {
    return self.operands[1].value
  }
}

public final class DestroyAddressOp: PrimOp {
  public init(_ value: Value) {
    super.init(opcode: .destroyAddress,
               type: BottomType.shared, category: .object)
    self.addOperands([Operand(owner: self, value: value)])
  }

  public var value: Value {
    return self.operands[0].value
  }
}

public final class FunctionRefOp: PrimOp {
  public let function: Continuation

  public init(continuation: Continuation) {
    self.function = continuation
    super.init(opcode: .functionRef, type: continuation.type, category: .object)
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
  public init(constructor: String, type: Value, argument: Value?) {
    self.constructor = constructor
    self.dataType = type
    super.init(opcode: .dataInit, type: type, category: .object)
    if let argVal = argument {
      self.addOperands([Operand(owner: self, value: argVal)])
    }
  }

  public var argumentTuple: Value? {
    guard !self.operands.isEmpty else {
      return nil
    }
    return operands[0].value
  }

  public override var result: Value? {
    return self
  }
}

public final class TupleOp: PrimOp {
  init(arguments: [Value]) {
    let ty = TupleType(elements: arguments.map({$0.type}), category: .object)
    super.init(opcode: .tuple, type: ty, category: .object)
    self.addOperands(arguments.map { Operand(owner: self, value: $0) })
  }

  public override var result: Value? {
    return self
  }
}

public final class TupleElementAddressOp: PrimOp {
  public let index: Int
  init(tuple: Value, index: Int) {
    guard let tupleTy = tuple.type as? TupleType else {
      fatalError()
    }
    self.index = index
    super.init(opcode: .tupleElementAddress,
               type: tupleTy.elements[index], category: .address)
    self.addOperands([ Operand(owner: self, value: tuple) ])
  }

  public var tuple: Value {
    return self.operands[0].value
  }

  public override var result: Value? {
    return self
  }
}

public final class AllocBoxOp: PrimOp {
  public init(_ type: GIRType) {
    super.init(opcode: .allocBox, type: BoxType(type), category: .object)
    self.addOperands([Operand(owner: self, value: type)])
  }

  public override var result: Value? {
    return self
  }

  public var boxedType: GIRType {
    return self.operands[0].value
  }
}

public final class ProjectBoxOp: PrimOp {
  public init(_ box: Value, type: GIRType) {
    super.init(opcode: .projectBox, type: type, category: .address)
    self.addOperands([ Operand(owner: self, value: box) ])
  }

  public override var result: Value? {
    return self
  }

  public var boxValue: Value {
    return operands[0].value
  }
}

public final class LoadOp: PrimOp {
  public enum Ownership {
    case take
    case copy
  }

  public let ownership: Ownership

  public init(_ value: Value, _ ownership: Ownership) {
    self.ownership = ownership
    super.init(opcode: .load, type: value.type, category: .object)
    self.addOperands([ Operand(owner: self, value: value) ])
  }

  public override var result: Value? {
    return self
  }

  public var addressee: Value {
    return operands[0].value
  }
}

public final class StoreOp: PrimOp {
  public init(_ value: Value, to address: Value) {
    super.init(opcode: .store, type: value.type, category: .address)
    self.addOperands([
      Operand(owner: self, value: value),
      Operand(owner: self, value: address),
    ])
  }

  public override var result: Value? {
    return self
  }

  public var value: Value {
    return operands[0].value
  }

  public var address: Value {
    return operands[1].value
  }
}

public final class DeallocBoxOp: PrimOp {
  public init(_ box: Value) {
    super.init(opcode: .deallocBox, type: BottomType.shared, category: .object)
    self.addOperands([ Operand(owner: self, value: box) ])
  }

  public var box: Value {
    return operands[0].value
  }
}

public final class ThickenOp: PrimOp {
  public init(_ funcRef: FunctionRefOp) {
    super.init(opcode: .thicken, type: funcRef.type, category: .object)
    self.addOperands([ Operand(owner: self, value: funcRef) ])
  }

  public override var result: Value? {
    return self
  }

  public var function: Value {
    return operands[0].value
  }
}

public final class ForceEffectsOp: PrimOp {
  public init(_ retVal: Value, _ effects: [Value]) {
    super.init(opcode: .forceEffects,
               type: retVal.type, category: retVal.category)
    self.addOperands([ Operand(owner: self, value: retVal) ])
    self.addOperands(effects.map { Operand(owner: self, value: $0) })
  }

  public var subject: Value {
    return operands[0].value
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
  associatedtype Ret
  func visitAllocaOp(_ op: AllocaOp) -> Ret
  func visitApplyOp(_ op: ApplyOp) -> Ret
  func visitDeallocaOp(_ op: DeallocaOp) -> Ret
  func visitCopyValueOp(_ op: CopyValueOp) -> Ret
  func visitDestroyValueOp(_ op: DestroyValueOp) -> Ret
  func visitCopyAddressOp(_ op: CopyAddressOp) -> Ret
  func visitDestroyAddressOp(_ op: DestroyAddressOp) -> Ret
  func visitFunctionRefOp(_ op: FunctionRefOp) -> Ret
  func visitSwitchConstrOp(_ op: SwitchConstrOp) -> Ret
  func visitDataInitOp(_ op: DataInitOp) -> Ret
  func visitTupleOp(_ op: TupleOp) -> Ret
  func visitTupleElementAddress(_ op: TupleElementAddressOp) -> Ret
  func visitLoadOp(_ op: LoadOp) -> Ret
  func visitStoreOp(_ op: StoreOp) -> Ret
  func visitAllocBoxOp(_ op: AllocBoxOp) -> Ret
  func visitProjectBoxOp(_ op: ProjectBoxOp) -> Ret
  func visitDeallocBoxOp(_ op: DeallocBoxOp) -> Ret
  func visitThickenOp(_ op: ThickenOp) -> Ret
  func visitUnreachableOp(_ op: UnreachableOp) -> Ret
  func visitForceEffectsOp(_ op: ForceEffectsOp) -> Ret
}

extension PrimOpVisitor {
  public func visitPrimOp(_ code: PrimOp) -> Ret {
    switch code.opcode {
    case .noop:
      fatalError()
    // swiftlint:disable force_cast
    case .alloca: return self.visitAllocaOp(code as! AllocaOp)
    // swiftlint:disable force_cast
    case .apply: return self.visitApplyOp(code as! ApplyOp)
    // swiftlint:disable force_cast
    case .dealloca: return self.visitDeallocaOp(code as! DeallocaOp)
    // swiftlint:disable force_cast
    case .copyValue: return self.visitCopyValueOp(code as! CopyValueOp)
    // swiftlint:disable force_cast
    case .destroyValue: return self.visitDestroyValueOp(code as! DestroyValueOp)
    // swiftlint:disable force_cast
    case .copyAddress: return self.visitCopyAddressOp(code as! CopyAddressOp)
    // swiftlint:disable force_cast
    case .destroyAddress:
      return self.visitDestroyAddressOp(code as! DestroyAddressOp)
    // swiftlint:disable force_cast
    case .functionRef: return self.visitFunctionRefOp(code as! FunctionRefOp)
    // swiftlint:disable force_cast
    case .switchConstr: return self.visitSwitchConstrOp(code as! SwitchConstrOp)
    // swiftlint:disable force_cast
    case .dataInit: return self.visitDataInitOp(code as! DataInitOp)
    // swiftlint:disable force_cast
    case .tuple: return self.visitTupleOp(code as! TupleOp)
      // swiftlint:disable force_cast line_length
    case .tupleElementAddress: return self.visitTupleElementAddress(code as! TupleElementAddressOp)
    // swiftlint:disable force_cast
    case .unreachable: return self.visitUnreachableOp(code as! UnreachableOp)
    // swiftlint:disable force_cast
    case .load: return self.visitLoadOp(code as! LoadOp)
    // swiftlint:disable force_cast
    case .store: return self.visitStoreOp(code as! StoreOp)
    // swiftlint:disable force_cast
    case .allocBox: return self.visitAllocBoxOp(code as! AllocBoxOp)
    // swiftlint:disable force_cast
    case .projectBox: return self.visitProjectBoxOp(code as! ProjectBoxOp)
    // swiftlint:disable force_cast
    case .deallocBox: return self.visitDeallocBoxOp(code as! DeallocBoxOp)
    // swiftlint:disable force_cast
    case .thicken: return self.visitThickenOp(code as! ThickenOp)
    // swiftlint:disable force_cast
    case .forceEffects: return self.visitForceEffectsOp(code as! ForceEffectsOp)
    }
  }
}
