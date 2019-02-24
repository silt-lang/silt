/// SyntaxDumper.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Rainbow

public class SyntaxDumper<StreamType: TextOutputStream>: Writer<StreamType> {
  let converter: SourceLocationConverter

  public init(
    stream: inout StreamType,
    converter: SourceLocationConverter,
    indentationWidth: Int = 2
  ) {
    self.converter = converter
    super.init(stream: &stream, indentationWidth: indentationWidth)
  }

  public func writeLoc(_ loc: SourceLocation?) {
    if let loc = loc {
      let url = URL(fileURLWithPath: loc.file)
      write(" ")
      write(url.lastPathComponent.yellow)
      write(":")
      write("\(loc.line)".cyan)
      write(":")
      write("\(loc.column)".cyan)
    }
  }

  public func dump(_ node: Syntax, root: Bool = true) {
    write("(")
    switch node {
    case let node as TokenSyntax:
      switch node.tokenKind {
      case .identifier(let name):
        write("identifier".green.bold)
        write(" \"\(name)\"".red)
      default:
        write("\(node.tokenKind)".green.bold)
      }
      writeLoc(node.endLocation(converter: self.converter))
    default:
      write("\(node.raw.kind)".magenta.bold)
      writeLoc(node.startLocation(converter: self.converter))
      withIndent {
        for child in node.children {
          writeLine()
          dump(child, root: false)
        }
      }
    }
    write(")")
    if root {
      writeLine()
    }
  }
}
