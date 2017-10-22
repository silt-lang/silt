//===------------------ RawSyntax.swift - Raw Syntax nodes ----------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
// This file contains modifications from the Silt Langauge project. These
// modifications are released under the MIT license, a copy of which is
// available in the repository.
//
//===----------------------------------------------------------------------===//

import Foundation

/// Represents the raw tree structure underlying the syntax tree. These nodes
/// have no notion of identity and only provide structure to the tree. They
/// are immutable and can be freely shared between syntax nodes.
indirect enum RawSyntax {
  /// A tree node with a kind, an array of children, and a source presence.
  case node(SyntaxKind, [RawSyntax], SourcePresence)

  /// A token with a token kind, leading trivia, trailing trivia, and a source
  /// presence.
  case token(TokenKind, Trivia, Trivia, SourcePresence, SourceRange?)

  /// The syntax kind of this raw syntax.
  var kind: SyntaxKind {
    switch self {
    case .node(let kind, _, _): return kind
    case .token(_, _, _, _, _): return .token
    }
  }

  var tokenKind: TokenKind? {
    switch self {
    case .node(_, _, _): return nil
    case .token(let kind, _, _, _, _): return kind
    }
  }

  /// The layout of the children of this Raw syntax node.
  var layout: [RawSyntax] {
    switch self {
    case .node(_, let layout, _): return layout
    case .token(_, _, _, _, _): return []
    }
  }

  /// The source presence of this node.
  var presence: SourcePresence {
    switch self {
    case .node(_, _, let presence): return presence
    case .token(_, _, _, let presence, _): return presence
    }
  }

  /// Whether this node is present in the original source.
  var isPresent: Bool {
    return presence == .present
  }

  /// Whether this node is missing from the original source.
  var isMissing: Bool {
    return presence == .missing
  }

  /// Creates a RawSyntax node that's marked missing in the source with the
  /// provided kind and layout.
  /// - Parameters:
  ///   - kind: The syntax kind underlying this node.
  ///   - layout: The children of this node.
  /// - Returns: A new RawSyntax `.node` with the provided kind and layout, with
  ///            `.missing` source presence.
  static func missing(_ kind: SyntaxKind) -> RawSyntax {
    return .node(kind, [], .missing)
  }

  /// Creates a RawSyntax token that's marked missing in the source with the
  /// provided kind and no leading/trailing trivia.
  /// - Parameter kind: The token kind.
  /// - Returns: A new RawSyntax `.token` with the provided kind, no
  ///            leading/trailing trivia, and `.missing` source presence.
  static func missingToken(_ kind: TokenKind) -> RawSyntax {
    return .token(kind, [], [], .missing, nil)
  }

  /// Returns a new RawSyntax node with the provided layout instead of the
  /// existing layout.
  /// - Note: This function does nothing with `.token` nodes --- the same token
  ///         is returned.
  /// - Parameter newLayout: The children of the new node you're creating.
  func replacingLayout(_ newLayout: [RawSyntax]) -> RawSyntax {
    switch self {
    case let .node(kind, _, presence): return .node(kind, newLayout, presence)
    case .token(_, _, _, _, _): return self
    }
  }

  /// Creates a new RawSyntax with the provided child appended to its layout.
  /// - Parameter child: The child to append
  /// - Note: This function does nothing with `.token` nodes --- the same token
  ///         is returned.
  /// - Return: A new RawSyntax node with the provided child at the end.
  func appending(_ child: RawSyntax) -> RawSyntax {
    var newLayout = layout
    newLayout.append(child)
    return replacingLayout(newLayout)
  }

  /// Returns the child at the provided cursor in the layout.
  /// - Parameter index: The index of the child you're accessing.
  /// - Returns: The child at the provided index.
  subscript<CursorType: RawRepresentable>(_ index: CursorType) -> RawSyntax
    where CursorType.RawValue == Int {
      return layout[index.rawValue]
  }

  /// Replaces the child at the provided index in this node with the provided
  /// child.
  /// - Parameters:
  ///   - index: The index of the child to replace.
  ///   - newChild: The new child that should occupy that index in the node.
  func replacingChild(_ index: Int,
                      with newChild: RawSyntax) -> RawSyntax {
    precondition(index < layout.count, "Cursor \(index) reached past layout")
    var newLayout = layout
    newLayout[index] = newChild
    return replacingLayout(newLayout)
  }
}

extension RawSyntax {
  /// Prints the RawSyntax node, and all of its children, to the provided
  /// stream. This implementation must be source-accurate.
  /// - Parameter stream: The stream on which to output this node.
  func writeSourceText<Target: TextOutputStream>(to target: inout Target,
                                                 includeImplicit: Bool) {
    switch self {
    case .node(_, let layout, _):
      for child in layout {
        child.writeSourceText(to: &target, includeImplicit: includeImplicit)
      }
    case let .token(kind, leadingTrivia, trailingTrivia, presence, _):
      switch presence {
      case .present,
           .implicit where includeImplicit:
        for piece in leadingTrivia {
          piece.writeSourceText(to: &target)
        }
        target.write(kind.text)
        for piece in trailingTrivia {
          piece.writeSourceText(to: &target)
        }
      default: break
      }
    }
  }
}
