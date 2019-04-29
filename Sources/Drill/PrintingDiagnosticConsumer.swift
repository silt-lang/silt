/// PrintingDiagnosticConsumer.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere
import Rainbow

public final
class PrintingDiagnosticConsumer<Target: TextOutputStream>: DiagnosticConsumer {
  private var output: Target
  private let converter: SourceLocationConverter

  public init(stream: inout Target) {
    self.output = stream
    let emptyTree = SyntaxFactory.makeSourceFileSyntax([])
    self.converter = SourceLocationConverter(file: "", tree: emptyTree)
  }

  public func handle(_ diagnostic: Diagnostic) {
    if let loc = diagnostic.sourceLocation(converter: converter) {
      printLoc(loc)
    }
    printMessage(diagnostic.message)
    for note in diagnostic.notes {
      if let loc = note.sourceLocation(converter: converter) {
        printLoc(loc)
      }
      printMessage(note.message)
    }
  }

  func printLoc(_ loc: SourceLocation) {
    let url = URL(fileURLWithPath: loc.file)
    output.write("\(url.lastPathComponent):\(loc.line):\(loc.column): ".bold)
  }

  func printMessage(_ message: Diagnostic.Message) {
    output.write(message.severity.coloring("\(message.severity): "))
    output.write("\(message.text.bold)\n")
  }

  public func finalize() {

  }
}

public protocol DelayedDiagnosticConsumer: DiagnosticConsumer {
  func attachAndDrain(_ converter: SourceLocationConverter)
}

public final class DelayedPrintingDiagnosticConsumer<Target: TextOutputStream> {
  private var output: Target
  public private(set) var converter: SourceLocationConverter?
  private var delayedDiagnostics = [Diagnostic]()

  public init(stream: inout Target, converter: SourceLocationConverter? = nil) {
    self.output = stream
    self.converter = converter
  }

  public func handle(_ diagnostic: Diagnostic) {
    self.delayedDiagnostics.append(diagnostic)
    guard let converter = self.converter else {
      return
    }
    self.attachAndDrain(converter)
  }

  func printLoc(_ loc: SourceLocation) {
    let url = URL(fileURLWithPath: loc.file)
    output.write("\(url.lastPathComponent):\(loc.line):\(loc.column): ".bold)
  }

  func printMessage(_ message: Diagnostic.Message) {
    output.write(message.severity.coloring("\(message.severity): "))
    output.write("\(message.text.bold)\n")
  }

  public func finalize() {

  }
}

extension DelayedPrintingDiagnosticConsumer: DelayedDiagnosticConsumer {
  public func attachAndDrain(_ converter: SourceLocationConverter) {
    self.converter = converter
    for diagnostic in self.delayedDiagnostics {
      if let loc = diagnostic.sourceLocation(converter: converter) {
        printLoc(loc)
      }
      printMessage(diagnostic.message)
      for note in diagnostic.notes {
        if let loc = note.sourceLocation(converter: converter) {
          printLoc(loc)
        }
        printMessage(note.message)
      }
    }
    self.delayedDiagnostics.removeAll()
  }
}

extension Diagnostic.Message.Severity {
  func coloring(_ string: String) -> String {
    switch self {
    case .error: return string.red.bold
    case .warning: return string.magenta.bold
    case .note: return string.green.bold
    }
  }
}
