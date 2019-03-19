/// GIRWriter.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere
import Seismography

extension GIRModule {
  public func dump() {
    let stream = FileHandle.standardOutput
    stream.write("module \(self.name) where")
    stream.write("\n")
    for scope in topLevelScopes {
      scope.dump()
    }
  }
}

extension PrimOp {
  public func dump() {
    var stream = FileHandle.standardOutput
    GIRWriter(stream: &stream).writePrimOp(self)
  }
}

extension Continuation {
  public func dump() {
    print("\(self.name)(", terminator: "")
    self.parameters.forEach { param in
      param.dump()
    }
    print("):")
  }
}

extension Parameter {
  public func dump() {
    print("%\(self.index) : \(self.type)", terminator: "")
  }
}

public final class GIRWriter<StreamType: TextOutputStream>: Writer<StreamType> {
  private struct GID: Comparable, CustomStringConvertible {
    enum Kind: Int, Comparable {
      case bbLikeContinuation = 0
      case ssaValue = 1

      static func == (lhs: Kind, rhs: Kind) -> Bool {
        return lhs.rawValue == rhs.rawValue
      }
      static func < (lhs: Kind, rhs: Kind) -> Bool {
        return lhs.rawValue < rhs.rawValue
      }
    }

    let kind: Kind
    let number: Int

    static func == (lhs: GID, rhs: GID) -> Bool {
      return lhs.kind == rhs.kind && lhs.number == rhs.number
    }
    static func < (lhs: GID, rhs: GID) -> Bool {
      if lhs.kind < rhs.kind {
        return true
      }
      if lhs.number < rhs.number {
        return true
      }
      return false
    }

    var description: String {
      switch self.kind {
      case .bbLikeContinuation:
        return "bb\(self.number)"
      case .ssaValue:
        return "%\(self.number)"
      }
    }
  }

  func writeSchedule(_ schedule: Schedule) {
    guard !schedule.blocks.isEmpty else { return }

    let scheduleName = schedule.blocks[0].parent.name
    self.write("@")
    self.write(scheduleName.string)
    self.write(" : ")
    self.visitType(schedule.blocks[0].parent.type)
    self.writeLine(" {")
    self.writeScheduleBlocks(schedule)
    self.write("} -- end gir function ")
    self.write(scheduleName.string)
    self.writeLine()
  }

  func writePrimOp(_ primOp: PrimOp) {
    self.setContext(nil)
    _ = self.getID(of: primOp)
    self.writeBlockPrimOp(primOp)
  }

  func writeScheduleBlocks(_ schedule: Schedule) {
    for block in schedule.blocks {
      self.writeBlock(block, in: schedule)
      self.writeLine()
    }
  }

  func writeBlock(_ block: Schedule.Block, in schedule: Schedule) {
    self.writeBlockArgumentUses(block, in: schedule)

    self.write(self.getID(for: block.parent, in: schedule).description)
    self.writeBlockArguments(block, in: schedule)
    self.write(":")

    self.writeLine()
    for op in block.primops {
      self.writeBlockPrimOp(op, in: schedule)
    }
  }

  func writeBlockPrimOp(_ op: PrimOp, in schedule: Schedule? = nil) {
    self.write("  ")
    if let result = op.result {
      self.write(self.getID(of: result, in: schedule).description)
      self.write(" = ")
    }

    self.write(op.opcode.rawValue)
    self.write(" ")
    self.visitPrimOp(op)
    self.writeUsersOfPrimOp(op, in: schedule)
    self.writeLine()
  }

  func writeBlockArguments(
    _ block: Schedule.Block, in schedule: Schedule? = nil) {
    guard !block.parent.parameters.isEmpty else { return }

    self.write("(")
    let params = block.parent.parameters
    self.write(self.getID(of: params[0], in: schedule).description)
    self.write(" : ")
    self.visitType(params[0].type)
    for param in params.dropFirst() {
      self.write("; ")
      self.write(self.getID(of: param, in: schedule).description)
      self.write(" : ")
      self.visitType(param.type)
    }
    self.write(")")
  }

  func writeBlockArgumentUses(
    _ block: Schedule.Block, in schedule: Schedule? = nil) {
    guard !block.parent.parameters.isEmpty else { return }

    for param in block.parent.parameters {
      guard param.hasUsers else {
        continue
      }

      self.write("-- \(self.getID(of: param, in: schedule))")
      self.padToColumn(50)
      self.write("-- users: ")

      var userIDs = [GID]()
      for op in param.users {
        userIDs.append(self.getID(of: op.user, in: schedule))
      }

      // swiftlint:disable opening_brace
      self.interleave(userIDs,
                      { id in self.write(id.description) },
                      { self.write(", ") })
      self.writeLine()
    }
  }

  func writeUsersOfPrimOp(_ op: PrimOp, in schedule: Schedule? = nil) {
    guard let result = op.result else {
      self.padToColumn(50)
      self.write("-- id: \(self.getID(of: op, in: schedule))")
      return
    }

    guard result.hasUsers else {
      return
    }

    var userIDs = [GID]()
    for op in result.users {
      userIDs.append(self.getID(of: op.user, in: schedule))
    }

    self.padToColumn(50)
    self.write("-- user")
    if userIDs.count != 1 {
      self.write("s")
    }
    self.write(": ")
    self.interleave(userIDs, { self.write("\($0)") }, { self.write(", ") })
  }

  var currentSchedule: Schedule?
  var blocksContsToIDs: [Continuation: Int] = [:]
  var valuesToIDs: [Value: Int] = [:]

  private func setContext(_ scope: Schedule?) {
    guard self.currentSchedule !== scope else {
      return
    }

    self.blocksContsToIDs.removeAll()
    self.valuesToIDs.removeAll()
    self.currentSchedule = scope
  }

  private func getID(for cont: Continuation, in scope: Schedule) -> GID {
    self.setContext(scope)

    if self.blocksContsToIDs.isEmpty {
      for (idx, b) in scope.blocks.enumerated() {
        self.blocksContsToIDs[b.parent] = idx
      }
    }

    return GID(kind: .bbLikeContinuation,
              number: self.blocksContsToIDs[cont, default: -1])
  }

  private func getID(of value: Value, in scope: Schedule? = nil) -> GID {
    self.setContext(scope ?? self.currentSchedule)

    guard self.valuesToIDs.isEmpty else {
      return GID(kind: .ssaValue, number: self.valuesToIDs[value, default: -1])
    }

    if let scope = scope {
      var idx = 0
      for BB in scope.blocks {
        for op in BB.parent.parameters {
          self.valuesToIDs[op] = idx
          idx += 1
        }

        for op in BB.primops {
          if let result = op.result {
            self.valuesToIDs[op] = idx
            self.valuesToIDs[result] = idx
          } else {
            self.valuesToIDs[op] = idx
          }
          idx += 1
        }
      }
    } else if let primOp = value as? PrimOp {
      var idx = 0
      if let result = primOp.result {
        self.valuesToIDs[primOp] = idx
        self.valuesToIDs[result] = idx
      } else {
        self.valuesToIDs[primOp] = idx
      }
      idx += 1
      for operand in primOp.operands {
        self.valuesToIDs[operand.value] = idx
        idx += 1
      }
    } else {
      fatalError(
        "Context value must populate ID cache with a schedule or a primop")
    }
    return GID(kind: .ssaValue, number: self.valuesToIDs[value, default: -1])
  }
}

extension GIRWriter: PrimOpVisitor {
  public func visitStoreOp(_ op: StoreOp) {
    self.write(self.getID(of: op.value).description)
    self.write(" to ")
    self.write(self.getID(of: op.address).description)
  }

  public func visitLoadOp(_ op: LoadOp) {
    switch op.ownership {
    case .copy:
      self.write(" [copy] ")
    case .take:
      self.write(" [take] ")
    }
    self.write(self.getID(of: op.addressee).description)
    self.write(" : ")
    self.visitType(op.addressee.type)
  }

  public func visitProjectBoxOp(_ op: ProjectBoxOp) {
    self.write(self.getID(of: op.boxValue).description)
    self.write(" : ")
    self.visitType(op.boxValue.type)
  }

  public func visitAllocBoxOp(_ op: AllocBoxOp) {
    self.visitType(op.boxedType)
  }

  public func visitDeallocBoxOp(_ op: DeallocBoxOp) {
    self.write(self.getID(of: op.box).description)
    self.write(" : ")
    self.visitType(op.box.type)
  }

  public func visitAllocaOp(_ op: AllocaOp) {
    self.visitType(op.addressType)
  }

  public func visitDeallocaOp(_ op: DeallocaOp) {
    self.write(self.getID(of: op.addressValue).description)
    self.write(" : ")
    self.visitType(op.addressValue.type)
  }

  public func visitApplyOp(_ op: ApplyOp) {
    self.write(self.getID(of: op.callee).description)
    self.write("(")
    self.interleave(op.arguments,
                    { self.write(self.getID(of: $0.value).description) },
                    { self.write(" ; ") })
    self.write(") : ")
    self.visitType(op.callee.type)
  }

  public func visitCopyValueOp(_ op: CopyValueOp) {
    self.write(self.getID(of: op.value.value).description)
  }

  public func visitDestroyValueOp(_ op: DestroyValueOp) {
    self.write(self.getID(of: op.value.value).description)
  }

  public func visitCopyAddressOp(_ op: CopyAddressOp) {
    self.write(self.getID(of: op.value).description)
    self.write(" to ")
    self.write(self.getID(of: op.address).description)
    self.write(" : ")
    self.visitType(op.type)
  }

  public func visitDestroyAddressOp(_ op: DestroyAddressOp) {
    self.write(self.getID(of: op.value).description)
    self.write(" : ")
    self.visitType(op.value.type)
  }

  public func visitSwitchConstrOp(_ op: SwitchConstrOp) {
    self.write(self.getID(of: op.matchedValue).description)
    self.write(" : ")
    self.visitType(op.matchedValue.type)
    self.write(" ; ")
    self.interleave(op.patterns,
                    { arg in
                      self.write(arg.pattern)
                      self.write(" : ")
                      self.write(self.getID(of: arg.apply).description)
                    },
                    { self.write(" ; ") })
    guard let defaultDest = op.`default` else {
      return
    }
    self.write(" ; ")
    self.write("default : ")
    self.write(self.getID(of: defaultDest).description)
  }

  public func visitFunctionRefOp(_ op: FunctionRefOp) {
    self.write("@")
    guard let schedule = self.currentSchedule else {
      self.write(op.function.name.string)
      return
    }
    guard let entryBlock = schedule.blocks.first else {
      self.write(op.function.name.string)
      return
    }
    guard
      op.function.name.string.starts(with: entryBlock.parent.name.string)
    else {
      self.write(op.function.name.string)
      return
    }
    self.write(self.getID(for: op.function, in: schedule).description)
  }

  public func visitDataInitOp(_ op: DataInitOp) {
    self.visitType(op.dataType)
    self.write(" ; ")
    self.write(op.constructor)
    guard !op.operands.isEmpty else {
      return
    }
    self.write(" ; ")
    self.interleave(op.operands,
                    { self.write(self.getID(of: $0.value).description) },
                    { self.write(" ; ") })
  }

  public func visitTupleOp(_ op: TupleOp) {
    self.write("(")
    self.interleave(op.operands,
                    { self.write(self.getID(of: $0.value).description) },
                    { self.write(" ; ") })
    self.write(")")
  }

  public func visitTupleElementAddress(_ op: TupleElementAddressOp) {
    self.write(self.getID(of: op.tuple).description)
    self.write(" : ")
    self.visitType(op.tuple.type)
    self.write(" ; ")
    self.write("\(op.index)")
  }

  public func visitThickenOp(_ op: ThickenOp) {
    self.write(self.getID(of: op.function).description)
  }

  public func visitForceEffectsOp(_ op: ForceEffectsOp) {
    self.interleave(op.operands,
                    { self.write(self.getID(of: $0.value).description) },
                    { self.write(" ; ") })
  }

  public func visitUnreachableOp(_ op: UnreachableOp) {}
}

extension GIRWriter: TypeVisitor {
  public func visitTypeCommon(_ type: GIRType) {
    if type.category == .address {
      self.write("*")
    }
  }

  public func visitGIRExprType(_ type: GIRExprType) {
    self.visitTypeCommon(type)
    self.write(type.expr.diagnosticSourceText)
  }

  public func visitTypeMetadataType(_ type: TypeMetadataType) {
    self.visitTypeCommon(type)
  }
  public func visitTypeType(_ type: TypeType) {
    self.visitTypeCommon(type)
    self.write("Type")
  }
  public func visitArchetypeType(_ type: ArchetypeType) {
    self.visitTypeCommon(type)
    self.write("τ_\(type.index)")
  }
  public func visitParameterizedType(_ type: ParameterizedType) {
    self.visitTypeCommon(type)
  }
  public func visitDataType(_ type: DataType) {
    self.visitTypeCommon(type)
    self.write(type.name.string)
  }
  public func visitBoxType(_ type: BoxType) {
    self.visitTypeCommon(type)
    self.write("@box ")
    self.visitType(type.underlyingType)
  }
  public func visitRecordType(_ type: RecordType) {
    self.visitTypeCommon(type)
    self.write(type.name.string)
  }
  public func visitFunctionType(_ type: FunctionType) {
    self.visitTypeCommon(type)
    guard !type.arguments.isEmpty else {
      return self.visitType(type.returnType)
    }
    self.write("(")
    self.interleave(type.arguments,
                    { self.visitType($0) },
                    { self.write(" ; ") })
    self.write(") -> ")
    return self.visitType(type.returnType)
  }
  public func visitTupleType(_ type: TupleType) {
    self.visitTypeCommon(type)
    self.write("(")
    self.interleave(type.elements,
                    { self.visitType($0) },
                    { self.write(" , ") })
    self.write(")")
  }
  public func visitSubstitutedType(_ type: SubstitutedType) {
    self.visitType(type.substitutee)
    self.write(" ")
    self.interleave(type.substitutions,
                    { self.visitType($1) },
                    { self.write(" ") })
  }
  public func visitBottomType(_ type: BottomType) {
    self.visitTypeCommon(type)
    self.write("_")
  }
}

/*

func name(for value: Value) -> String {
  switch value {
  case let type as DataType:
    return escape(type.name)
  case let type as RecordType:
    return escape(type.name)
  case let type as ArchetypeType:
    let p = type.parent
    return "\(name(for: p)).\(escape(p.parameter(at: type.index).name))"
  case let type as SubstitutedType:
    var s = "\(name(for: type.substitutee))["
    var substs = [String]()
    for param in type.substitutee.parameters {
      if let subst = type.substitutions[param.archetype] {
        substs.append(name(for: subst))
      } else {
        substs.append("_")
      }
    }
    s += substs.joined(separator: ", ") + "]"
    return s
  case let type as FunctionType:
    guard !type.arguments.isEmpty else {
      return name(for: type.returnType)
    }
    let args = type.arguments
                   .map(name(for:))
                   .joined(separator: ", ")
    return "(\(args)) -> \(name(for: type.returnType))"
  case is TypeMetadataType:
    return "TypeMetadata"
  case is TypeType:
    return "Type"
  case is BottomType:
    return "_"
  case is Continuation:
    return "@\(escape(value.name))"
  case is Parameter:
    return "%\(escape(value.name))"
  case is GIRExprType:
    return "TYPE"
  default:
    fatalError("attempt to serialize unknown value \(value)")
  }
}
 */
