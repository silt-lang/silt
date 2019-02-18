//
//  Shim.swift
//  Lithosphere
//
//  Created by Robert Widmann on 2/1/19.
//

extension TokenKind {
  public static var arrow: TokenKind {
    return .identifier("->")
  }
}

extension Syntax {
  /// A description of this node including implicitly-synthesized tokens.
  public var shinedSourceText: String {
    var s = ""
    self.writeSourceText(to: &s, includeImplicit: true)
    return s
  }

  public var triviaFreeSourceText: String {
    var s = ""
    self.writeSourceText(to: &s, includeImplicit: false, includeTrivia: false)
    return s
  }

  public var diagnosticSourceText: String {
    var s = ""
    self.formatSourceText(to: &s)
    return s
  }
}

extension Syntax {
  /// Prints the raw value of this node to the provided stream.
  /// - Parameter stream: The stream to which to print the raw tree.
  public func writeSourceText<Target: TextOutputStream>(
    to target: inout Target, includeImplicit: Bool,
    includeTrivia: Bool = true) {
    data.raw.writeSourceText(to: &target, includeImplicit: includeImplicit,
                             includeTrivia: includeTrivia)
  }

  /// Prints the raw value of this node to the provided stream.
  /// - Parameter stream: The stream to which to print the raw tree.
  public func formatSourceText<Target: TextOutputStream>(
    to target: inout Target) {
    data.raw.formatSourceText(to: &target)
  }
}

extension RawSyntax {
  /// Prints the RawSyntax node, and all of its children, to the provided
  /// stream. This implementation must be source-accurate.
  /// - Parameter stream: The stream on which to output this node.
  func writeSourceText<Target: TextOutputStream>(
    to target: inout Target, includeImplicit: Bool, includeTrivia: Bool) {
    switch self.data {
    case .node(_, let layout):
      for child in layout {
        child?.writeSourceText(to: &target, includeImplicit: includeImplicit,
                               includeTrivia: includeTrivia)
      }
    case let .token(kind, leadingTrivia, trailingTrivia):
      switch presence {
      case .present,
           .implicit where includeImplicit:
        if includeTrivia {
          for piece in leadingTrivia {
            piece.writeSourceText(to: &target)
          }
        }
        target.write(kind.text)
        if includeTrivia {
          for piece in trailingTrivia {
            piece.writeSourceText(to: &target)
          }
        }
      default: break
      }
    }
  }

  func formatSourceText<Target: TextOutputStream>(
    to target: inout Target) {
    switch self.data {
    case .node(_, let layout):
      for child in layout {
        child?.formatSourceText(to: &target)
      }
    case let .token(kind, _, _):
      switch presence {
      case .present:
        target.write(kind.text)
        TriviaPiece.spaces(1).writeSourceText(to: &target)
      default: break
      }
    }
  }
}
