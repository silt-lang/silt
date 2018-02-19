//
//  PrimOp.swift
//  OuterCore
//
//  Created by Robert Widmann on 2/20/18.
//

public class PrimOp: Value {
  public enum Code: String {
    case noop
    case apply
    case copy_value
    case destroy_value
  }

  private var allOperands: [Operand] = []

  public let opcode: Code
  public var operands: [Operand] {
    return self.allOperands
  }

  public var result: Value? {
    return nil
  }

  init(opcode: Code) {
    self.opcode = opcode
    super.init(name: self.opcode.rawValue, type: BottomType.shared)
  }

  fileprivate func addOperands(_ ops: [Operand]) {
    self.allOperands.append(contentsOf: ops)
  }
}

public final class NoOp: PrimOp {
  public init() {
    super.init(opcode: .noop)
  }
}

public final class ApplyOp: PrimOp {
  public init(_ fnVal: Value, _ args: [Value]) {
    super.init(opcode: .apply)
    self.addOperands([Operand(owner: self, value: fnVal)] + args.map({ arg in
      return Operand(owner: self, value: arg)
    }))
  }

  public override var result: Value? {
    return self
  }

  var callee: Value {
    return self.operands[0].value
  }

  var arguments: ArraySlice<Operand> {
    return self.operands.dropFirst()
  }

  public override func dump() {
    print(self.opcode.rawValue, terminator: " ")
    self.callee.dump()
    print("(", terminator: "")
    for arg in self.arguments {
      print(arg.value.name, terminator: "")
    }
    print(")", terminator: "")
    print("")
  }
}

public final class CopyValueOp: PrimOp {
  public init(_ value: Value) {
    super.init(opcode: .copy_value)
    self.addOperands([Operand(owner: self, value: value)])
  }

  public override var result: Value? {
    return self
  }

  var value: Operand {
    return self.operands[0]
  }

  public override func dump() {
    print(self.opcode.rawValue, terminator: " ")
    self.value.dump()
    print("")
  }
}

public final class DestroyValueOp: PrimOp {
  public init(_ value: Value) {
    super.init(opcode: .destroy_value)
    self.addOperands([Operand(owner: self, value: value)])
  }

  var value: Operand {
    return self.operands[0]
  }

  public override func dump() {
    print(self.opcode.rawValue, terminator: " ")
    self.value.dump()
    print("")
  }
}

public protocol PrimOpVisitor {
  func visitApplyOp(_ op: ApplyOp)
  func visitCopyValueOp(_ op: CopyValueOp)
  func visitDestroyValueOp(_ op: DestroyValueOp)
}

extension PrimOpVisitor {
  public func visitPrimOp(_ code: PrimOp) {
    switch code.opcode {
    case .noop:
      fatalError()
    case .apply: self.visitApplyOp(code as! ApplyOp)
    case .copy_value: self.visitCopyValueOp(code as! CopyValueOp)
    case .destroy_value: self.visitDestroyValueOp(code as! DestroyValueOp)
    }
  }
}
