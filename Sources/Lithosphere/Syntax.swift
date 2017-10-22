//===-------------------- Syntax.swift - Syntax Protocol ------------------===//
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

/// A Syntax node represents a tree of nodes with tokens at the leaves.
/// Each node has accessors for its known children, and allows efficient
/// iteration over the children through its `children` property.
public class Syntax {
  /// The type of sequence containing the indices of present children.
  internal typealias PresentChildIndicesSequence =
    LazyFilterSequence<CountableRange<Int>>

  /// The root of the tree this node is currently in.
  internal let _root: SyntaxData
  
  /// The data backing this node.
  /// - note: This is unowned, because the reference to the root data keeps it
  ///         alive. This means there is an implicit relationship -- the data
  ///         property must be a descendent of the root. This relationship must
  ///         be preserved in all circumstances where Syntax nodes are created.
  internal unowned var data: SyntaxData

#if DEBUG
  func validate() {
    // This is for subclasses to override to perform structural validation.
  }
#endif

  /// Creates a Syntax node from the provided root and data.
  internal init(root: SyntaxData, data: SyntaxData) {
    self._root = root
    self.data = data
#if DEBUG
    validate()
#endif
  }

  /// Access the raw syntax assuming the node is a Syntax.
  var raw: RawSyntax {
    return data.raw
  }

  /// An iterator over children of this node.
  public var children: SyntaxChildren {
    return SyntaxChildren(node: self)
  }

  /// Whether or not this node it marked as `present`.
  public var isPresent: Bool {
    return raw.presence == .present
  }

  /// Whether or not this node it marked as `missing`.
  public var isMissing: Bool {
    return raw.presence == .missing
  }

  /// The parent of this syntax node, or `nil` if this node is the root.
  public var parent: Syntax? {
    guard let parentData = data.parent else { return nil }
    return Syntax.make(root: _root, data: parentData)
  }

  /// The index of this node in the parent's children.
  public var indexInParent: Int {
    return data.indexInParent
  }

  /// The root of the tree in which this node resides.
  public var root: Syntax {
    return Syntax.make(root: _root,  data: _root)
  }

  public var startLoc: SourceLocation? {
    if case .token(_, _, _, _, let range) = raw {
      return range?.start
    }
    guard let firstChild = child(at: 0) else { return nil }
    return firstChild.startLoc
  }

  public var endLoc: SourceLocation? {
    if case .token(_, _, _, _, let range) = raw {
      return range?.end
    }
    guard let lastChild = child(at: data.childCaches.count - 1) else { return nil }
    return lastChild.endLoc
  }

  /// The sequence of indices that correspond to child nodes that are not
  /// missing.
  ///
  /// This property is an implementation detail of `SyntaxChildren`.
  internal var presentChildIndices: PresentChildIndicesSequence {
    return raw.layout.indices.lazy.filter { self.raw.layout[$0].isPresent }
  }

  /// Gets the child at the provided index in this node's children.
  /// - Parameter index: The index of the child node you're looking for.
  /// - Returns: A Syntax node for the provided child, or `nil` if there
  ///            is not a child at that index in the node.
  public func child(at index: Int) -> Syntax? {
    guard raw.layout.indices.contains(index) else { return nil }
    if raw.layout[index].isMissing { return nil }
    return Syntax.make(root: _root, data: data.cachedChild(at: index))
  }

  public func child<Cursor: RawRepresentable>(at cursor: Cursor) -> Syntax?
    where Cursor.RawValue == Int {
      return child(at: cursor.rawValue)
  }

  /// A source-accurate description of this node.
  public var sourceText: String {
    var s = ""
    self.writeSourceText(to: &s, includeImplicit: false)
    return s
  }

  /// A description of this node including implicitly-synthesized tokens.
  public var shinedSourceText: String {
    var s = ""
    self.writeSourceText(to: &s, includeImplicit: true)
    return s
  }
}

extension Syntax {
  /// Prints the raw value of this node to the provided stream.
  /// - Parameter stream: The stream to which to print the raw tree.
  public func writeSourceText<Target: TextOutputStream>(to target: inout Target, includeImplicit: Bool) {
    data.raw.writeSourceText(to: &target, includeImplicit: includeImplicit)
  }
}

extension Syntax: Equatable {
  /// Determines if two nodes are equal to each other.
  public static func ==(lhs: Syntax, rhs: Syntax) -> Bool {
    return lhs.data === rhs.data
  }
}
