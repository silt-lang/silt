/// IRWriter.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public class Writer<StreamType: TextOutputStream> {
  var stream: StreamType
  var indentLevel = 0
  let indentationWidth: Int

  public init(stream: inout StreamType, indentationWidth: Int = 2) {
    self.stream = stream
    self.indentationWidth = indentationWidth
  }

  func indent() {
    indentLevel += indentationWidth
  }

  func dedent() {
    precondition(indentLevel >= indentationWidth,
                 "attempting to dedent beyond 0")
    indentLevel -= indentationWidth
  }

  func withIndent<T>(_ actions: () throws -> T) rethrows -> T {
    indent()
    defer { dedent() }
    return try actions()
  }

  func write(_ text: String) {
    stream.write(text)
  }

  func writeIndent() {
    stream.write(String(repeating: " ", count: indentLevel))
  }

  func writeLine(_ text: String = "") {
    writeIndent()
    stream.write(text + "\n")
  }

  func interleave<C: Collection>(
    _ seq: C, _ pr: (C.Element) -> Void, _ inter: () -> Void) {
    guard !seq.isEmpty else { return }

    pr(seq[seq.startIndex])
    for idx in seq.indices.dropFirst() {
      inter()
      pr(seq[idx])
    }
  }
}

public final class IRWriter<StreamType: TextOutputStream>: Writer<StreamType> {
  public func write(_ module: GIRModule) {
    writeLine("-- module: \"\(module.name)\"")
    writeLine()
    for data in module.knownDataTypes {
      write("data \(escape(data.name)) ")
      writeParameters(data)
      write("{\n")
      withIndent {
        for constr in data.constructors {
          writeIndent()
          write("\(escape(constr.name)) : ")
          write(constr.type)
          write("\n")
        }
      }
      writeLine("}")
      writeLine()
    }
    for record in module.knownRecordTypes {
      write("record \(escape(record.name)) ")
      writeParameters(record)
      write("{\n")
      withIndent {
        for field in record.fields {
          writeIndent()
          write("\(escape(field.name)) : ")
          write(field.type)
          write("\n")
        }
      }
      writeLine("}")
      writeLine()
    }
    for continuation in module.continuations {
      write(continuation)
      writeLine()
    }
  }

  public func writeParameters(_ type: ParameterizedType) {
    for param in type.parameters {
      write("(\(escape(param.value.name)) : ")
      write(param.value.type)
      write(") ")
    }
  }

  public func write(_ type: Type) {
    write(name(for: type))
  }

  public func write(_ parameter: Parameter, isLast: Bool) {
    write(name(for: parameter))
    write(" : ")
    if parameter.ownership == .borrowed {
      write("@borrowed ")
    }
    write(parameter.type)
    if !isLast {
      write(", ")
    }
  }

  public func write(_ continuation: Continuation) {
    write("\(name(for: continuation))(")
    for (idx, param) in continuation.parameters.enumerated() {
      write(param, isLast: idx == continuation.parameters.count - 1)
    }
    writeLine(")")
  }
}

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
  private struct ID: Comparable, CustomStringConvertible {
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

    static func == (lhs: ID, rhs: ID) -> Bool {
      return lhs.kind == rhs.kind && lhs.number == rhs.number
    }
    static func < (lhs: ID, rhs: ID) -> Bool {
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

  func writeBlockPrimOp(_ op: PrimOp, in schedule: Schedule) {
    self.write("  ")
    if let result = op.result {
      self.write(self.getID(of: result, in: schedule).description)
      self.write(" = ")
    }

    self.write(op.opcode.rawValue)
    self.write(" ")
    self.visitPrimOp(op)
    self.writeLine()
  }

  func writeBlockArguments(_ block: Schedule.Block, in schedule: Schedule) {
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

  func writeBlockArgumentUses(_ block: Schedule.Block, in schedule: Schedule) {
    guard !block.parent.parameters.isEmpty else { return }

    for param in block.parent.parameters {
      guard param.hasUsers else {
        continue
      }

      self.write("-- \(self.getID(of: param, in: schedule))")
      self.write("-- users: ")

      var userIDs = [ID]()
      for op in param.users {
        userIDs.append(self.getID(of: op.user, in: schedule))
      }

      self.interleave(userIDs,
                      { id in self.write(id.description) },
                      { self.write(", ") })
      self.writeLine()
    }
  }

  var currentSchedule: Schedule? = nil
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

  private func getID(for block: Schedule.Block, in scope: Schedule) -> ID {
    self.setContext(scope)

    if self.blocksToIDs.isEmpty {
      for (idx, b) in scope.blocks.enumerated() {
        self.blocksToIDs[b] = idx
      }
    }

    return ID(kind: .bbLikeContinuation, number: self.blocksToIDs[block, default: 0])
  }

  private func getID(of value: Value, in scope: Schedule) -> ID {
    self.setContext(scope)

    if self.valuesToIDs.isEmpty {
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
    }

    return ID(kind: .ssaValue, number: self.valuesToIDs[value, default: 0])
  }
}

extension GIRWriter: PrimOpVisitor {
  public func visitApplyOp(_ op: ApplyOp) {
    self.write(self.getID(of: op.callee, in: self.currentSchedule!).description)
    self.write("(")
    self.interleave(op.arguments,
                    { arg in self.write(self.getID(of: arg.value, in: self.currentSchedule!).description) },
                    { self.write(" ; ") })
    self.write(") : ")
    self.write(name(for: op.callee.type))
  }

  public func visitCopyValueOp(_ op: CopyValueOp) {
    self.write(self.getID(of: op.value.value, in: self.currentSchedule!).description)
  }

  public func visitDestroyValueOp(_ op: DestroyValueOp) {
    self.write(self.getID(of: op.value.value, in: self.currentSchedule!).description)
  }
}

extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    write(string.data(using: .utf8)!)
  }
}
