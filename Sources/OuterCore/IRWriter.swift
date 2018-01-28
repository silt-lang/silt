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
}

public final class IRWriter<StreamType: TextOutputStream>: Writer<StreamType> {
  public func write(_ module: Module) {
    writeLine("-- module: \"\(module.name)\"")
    writeLine()
    for data in module.knownDataTypes {
      writeLine("data \(data.name.string) {")
      for constr in data.constructors {
        write("\(constr.name.string) : ")
        write(constr.type)
        writeLine()
      }
      writeLine("}")
      writeLine()
    }
    for record in module.knownRecordTypes {
      writeLine("record \(record.name.string) {")
      for field in record.fields {
        write("\(field.name.string) : ")
        write(field.type)
        writeLine()
      }
      writeLine("}")
      writeLine()
    }
    for continuation in module.continuations {
      write(continuation)
      writeLine()
    }
  }

  public func write(_ type: Type) {
    switch type {
    case let type as DataType:
      write(type.name.string)
    case let type as TypeMetadataType:
      write(type.type)
      write(".metadata")
    case let type as FunctionType:
      write("(")
      for (idx, arg) in type.arguments.enumerated() {
        write(arg)
        if idx != type.arguments.count - 1 {
          write(", ")
        }
      }
      write(") -> ")
      write(type.returnType)
    case let type as RecordType:
      write(type.name.string)
    case is BottomType:
      write("⊥")
    default:
      fatalError("attempt to write unknown type: \(type)")
    }
  }

  public func write(_ parameter: Parameter, isLast: Bool) {
    write(asReference(parameter))
    write(parameter.type)
    if !isLast {
      write(", ")
    }
  }

  public func asReference(_ callee: Value) -> String {
    switch callee {
    case let callee as Continuation:
      return "@\(callee.name)"
    default:
      return "%\(callee.name)"
    }
  }

  public func write(_ continuation: Continuation) {
    write("\(asReference(continuation))(")
    for (idx, param) in continuation.parameters.enumerated() {
      write(param, isLast: idx == continuation.parameters.count - 1)
    }
    writeLine(") {")
    withIndent {
      if let call = continuation.call {
        let names = call.args.map(self.asReference).joined(separator: ", ")
        writeLine("\(asReference(call.callee))(\(names))")
      } else {
        writeLine("[empty]")
      }
    }
    writeLine("}")
  }
}
