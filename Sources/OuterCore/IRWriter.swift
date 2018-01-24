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

  func writeLine(_ text: String) {
    stream.write(String(repeating: " ", count: indentLevel))
    stream.write(text + "\n")
  }
}

public final class IRWriter<StreamType: TextOutputStream>: Writer<StreamType> {
  public func write(_ continuation: Continuation) {
    write("\(continuation.name)(")
    let paramDescs = continuation.parameters
                                 .map { "%\($0.name) : \($0.type)" }
                                 .joined(separator: ", ")
    write(paramDescs)
    write("):\n")
    withIndent {
      if let call = continuation.call {
        let names = call.args.map { "%\($0.name)" }
                             .joined(separator: ", ")
        writeLine("\(call.callee.name)(\(names))")
      }
    }
    write("\n")
  }
}
