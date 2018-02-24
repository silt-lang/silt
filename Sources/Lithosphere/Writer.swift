/// Trivia+Convenience.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

open class Writer<StreamType: TextOutputStream> {
  var stream: StreamType
  var indentLevel = 0
  let indentationWidth: Int

  public init(stream: inout StreamType, indentationWidth: Int = 2) {
    self.stream = stream
    self.indentationWidth = indentationWidth
  }

  public func indent() {
    indentLevel += indentationWidth
  }

  public func dedent() {
    precondition(indentLevel >= indentationWidth,
                 "attempting to dedent beyond 0")
    indentLevel -= indentationWidth
  }

  public func withIndent<T>(_ actions: () throws -> T) rethrows -> T {
    indent()
    defer { dedent() }
    return try actions()
  }

  public func write(_ text: String) {
    stream.write(text)
  }

  public func writeIndent() {
    stream.write(String(repeating: " ", count: indentLevel))
  }

  public func writeLine(_ text: String = "") {
    writeIndent()
    stream.write(text + "\n")
  }

  public func interleave<C: Collection>(
    _ seq: C, _ pr: (C.Element) -> Void, _ inter: () -> Void) {
    guard !seq.isEmpty else { return }

    pr(seq[seq.startIndex])
    for idx in seq.indices.dropFirst() {
      inter()
      pr(seq[idx])
    }
  }
}

extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    write(string.data(using: .utf8)!)
  }
}
