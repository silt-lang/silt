/// SyntaxDumper.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Rainbow

public class SyntaxDumper<StreamType: TextOutputStream> {
  var stream: StreamType
  var indent = 0

  public init(stream: inout StreamType) {
    self.stream = stream
  }

  public func withIndent(_ f: () -> Void) {
    indent += 2
    f()
    indent -= 2
  }

  public func write(_ string: String) {
    stream.write(String(repeating: " ", count: indent))
    stream.write(string)
  }

  public func line(_ string: String? = nil) {
    if let string = string { write(string) }
    stream.write("\n")
  }

  public func writeLoc(_ loc: SourceLocation?) {
    if let loc = loc {
      let url = URL(fileURLWithPath: loc.file)
      stream.write(" ")
      stream.write(url.lastPathComponent.yellow)
      stream.write(":")
      stream.write("\(loc.line)".cyan)
      stream.write(":")
      stream.write("\(loc.column)".cyan)
    }
  }

  public func dump(_ node: Syntax, root: Bool = true) {
    write("(")
    switch node {
    case let node as TokenSyntax:
      switch node.tokenKind {
      case .identifier(let name):
        stream.write("identifier".green.bold)
        stream.write(" \"\(name)\"".red)
      default:
        stream.write("\(node.tokenKind)".green.bold)
      }
      writeLoc(node.startLoc)
    default:
      stream.write("\(node.raw.kind)".magenta.bold)
      writeLoc(node.startLoc)
      withIndent {
        for child in node.children {
          line()
          dump(child, root: false)
        }
      }
    }
    stream.write(")")
    if root {
      line()
    }
  }
}
