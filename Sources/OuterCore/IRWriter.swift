/// IRWriter.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

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
    let args = type.arguments
                   .map(name(for:))
                   .joined(separator: ", ")
    return "(\(args)) -> \(name(for: type.returnType))"
  case is TypeMetadataType:
    return "TypeMetadata"
  case is TypeType:
    return "Type"
  case is BottomType:
    return "⊥"
  case is Continuation:
    return "@\(escape(value.name))"
  case is Parameter:
    return "%\(escape(value.name))"
  case is GIRType:
    return "TYPE"
  default:
    fatalError("attempt to serialize unknown value \(value)")
  }
}

func escape(_ name: String) -> String {
  if Set(name).intersection("@[] ,()->").isEmpty { return name }
  return "\"\(name)\""
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
    self.write(scheduleName)
    self.write(" : ")
    self.write(name(for: schedule.blocks[0].parent.type))
    self.writeLine(" {")
    self.writeScheduleBlocks(schedule)
    self.write("} -- end gir function ")
    self.write(scheduleName)
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

    self.write(self.getID(for: block, in: schedule).description)
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
    for param in params.dropFirst() {
      self.write(", ")
      self.write(self.getID(of: param, in: schedule).description)
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
  var blocksToIDs: [Schedule.Block: Int] = [:]
  var valuesToIDs: [Value: Int] = [:]

  private func setContext(_ scope: Schedule?) {
    guard self.currentSchedule !== scope else {
      return
    }

    self.blocksToIDs.removeAll()
    self.valuesToIDs.removeAll()
    self.currentSchedule = scope
  }

  private func getID(for block: Schedule.Block, in scope: Schedule) -> GID {
    self.setContext(scope)

    if self.blocksToIDs.isEmpty {
      for (idx, b) in scope.blocks.enumerated() {
        self.blocksToIDs[b] = idx
      }
    }

    return GID(kind: .bbLikeContinuation,
              number: self.blocksToIDs[block, default: 0])
  }

  private func getID(of value: Value, in scope: Schedule? = nil) -> GID {
    self.setContext(scope ?? self.currentSchedule)

    guard self.valuesToIDs.isEmpty else {
      return GID(kind: .ssaValue, number: self.valuesToIDs[value, default: 0])
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
  public func visitApplyOp(_ op: ApplyOp) {
    self.write(self.getID(of: op.callee).description)
    self.write("(")
    self.interleave(op.arguments,
                    { self.write(self.getID(of: $0.value).description) },
                    { self.write(" ; ") })
    self.write(") : ")
    self.write(name(for: op.callee.type))
  }

  public func visitCopyValueOp(_ op: CopyValueOp) {
    self.write(self.getID(of: op.value.value).description)
  }

  public func visitDestroyValueOp(_ op: DestroyValueOp) {
    self.write(self.getID(of: op.value.value).description)
  }

  public func visitSwitchConstrOp(_ op: SwitchConstrOp) {
    self.write(self.getID(of: op.matchedValue).description)
    self.write(" ; ")
    self.interleave(op.patterns,
                    { arg in
                      self.write(arg.pattern)
                      self.write(" : ")
                      self.write(self.getID(of: arg.apply).description)
                    },
                    { self.write(" ; ") })
  }

  public func visitFunctionRefOp(_ op: FunctionRefOp) {
    self.write("@")
    self.write(op.function.name)
  }

  public func visitDataInitSimpleOp(_ op: DataInitSimpleOp) {
    self.write(op.constructor)
  }

  public func visitUnreachableOp(_ op: UnreachableOp) {
  }
}
