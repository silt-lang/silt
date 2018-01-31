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
      write("data \(escape(data.name.string)) ")
      writeParameters(data)
      write("{\n")
      withIndent {
        for constr in data.constructors {
          writeIndent()
          write("\(escape(constr.name.string)) : ")
          write(constr.type)
          write("\n")
        }
      }
      writeLine("}")
      writeLine()
    }
    for record in module.knownRecordTypes {
      write("record \(escape(record.name.string)) ")
      writeParameters(record)
      write("{\n")
      withIndent {
        for field in record.fields {
          writeIndent()
          write("\(escape(field.name.string)) : ")
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
      write("(\(escape(param.value.name.string)) : ")
      write(param.value.type)
      write(") ")
    }
  }

  public func write(_ type: Type) {
    switch type {
    case let type as FunctionType:
      let pieces =
        type.arguments.map { escape(name(for: $0)) }
          .joined(separator: ", ")
      write("(\(pieces)) -> \(escape(name(for: type.returnType)))")
    default:
      write(escape(name(for: type)))
    }
  }

  public func write(_ parameter: Parameter, isLast: Bool) {
    write(asReference(parameter))
    write(" : ")
    write(parameter.type)
    if !isLast {
      write(", ")
    }
  }

  public func asReference(_ callee: Value) -> String {
    let escaped = escape(callee.name)
    if callee is Continuation {
      return "@\(escaped)"
    }
    return "%\(escaped)"
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

func name(for type: Type) -> String {
  switch type {
  case let type as DataType:
    return type.name.string
  case let type as RecordType:
    return type.name.string
  case let type as ArchetypeType:
    return "\(name(for: type.type)).\(type.index)"
  case let type as FunctionType:
    let args = type.arguments.map(name(for:)).joined(separator: ", ")
    return "(\(args)) -> \(name(for: type.returnType))"
  case is TypeMetadataType:
    return "TypeMetadata"
  case is TypeType:
    return "Type"
  case is BottomType:
    return "⊥"
  default:
    fatalError("attempt to write unknown type: \(type)")
  }
}

func escape(_ name: String) -> String {
  guard name.contains(" ") || name.contains(",") else { return name }
  return "\"\(name)\""
}
