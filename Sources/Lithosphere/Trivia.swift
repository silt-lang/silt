//===------------------- Trivia.swift - Source Trivia Enum ----------------===//
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

/// A contiguous stretch of a single kind of trivia. The constituent part of
/// a `Trivia` collection.
///
/// For example, four spaces would be represented by
/// `.spaces(4)`
///
/// In general, you should deal with the actual Trivia collection instead
/// of individual pieces whenever possible.
public enum TriviaPiece {
  /// A space ' ' character.
  case spaces(Int)

  /// A tab '\t' character.
  case tabs(Int)

  /// A vertical tab '\v' character.
  case verticalTabs(Int)

  /// A form-feed '\f' character.
  case formfeeds(Int)

  /// A newline '\n' character.
  case newlines(Int)

  /// A developer line comment, starting with '--'
  case comment(String)
}

extension TriviaPiece {
  /// Prints the provided trivia as they would be written in a source file.
  ///
  /// - Parameter stream: The stream to which to print the trivia.
  public func writeSourceText<
    Target: TextOutputStream>(to target: inout Target) {
    func printRepeated(_ character: String, count: Int) {
      for _ in 0..<count { target.write(character) }
    }
    switch self {
    case let .spaces(count): printRepeated(" ", count: count)
    case let .tabs(count): printRepeated("\t", count: count)
    case let .verticalTabs(count): printRepeated("\u{2B7F}", count: count)
    case let .formfeeds(count): printRepeated("\u{240C}", count: count)
    case let .newlines(count): printRepeated("\n", count: count)
    case let .comment(text): target.write(text)
    }
  }
}

/// A collection of leading or trailing trivia. This is the main data structure
/// for thinking about trivia.
public struct Trivia {
  internal(set) var pieces: [TriviaPiece]

  /// Creates Trivia with the provided underlying pieces.
  public init(pieces: [TriviaPiece]) {
    self.pieces = pieces
  }

  /// Creates Trivia with no pieces.
  public static var zero: Trivia {
    return Trivia(pieces: [])
  }

  /// Creates a new `Trivia` by appending the provided `TriviaPiece` to the end.
  public func appending(_ piece: TriviaPiece) -> Trivia {
    var copy = pieces
    copy.append(piece)
    return Trivia(pieces: copy)
  }

  /// Return a piece of trivia for some number of space characters in a row.
  public static func spaces(_ count: Int) -> Trivia {
    return [.spaces(count)]
  }

  /// Return a piece of trivia for some number of tab characters in a row.
  public static func tabs(_ count: Int) -> Trivia {
    return [.tabs(count)]
  }

  /// A vertical tab '\v' character.
  public static func verticalTabs(_ count: Int) -> Trivia {
    return [.verticalTabs(count)]
  }

  /// A form-feed '\f' character.
  public static func formfeeds(_ count: Int) -> Trivia {
    return [.formfeeds(count)]
  }

  /// Return a piece of trivia for some number of newline characters
  /// in a row.
  public static func newlines(_ count: Int) -> Trivia {
    return [.newlines(count)]
  }

  /// Return a piece of trivia for a single line of ('--') developer comment.
  public static func comment(_ text: String) -> Trivia {
    return [.comment(text)]
  }
}

/// Conformance for Trivia to the Collection protocol.
extension Trivia: Collection {
  public var startIndex: Int {
    return pieces.startIndex
  }

  public var endIndex: Int {
    return pieces.endIndex
  }

  public func index(after i: Int) -> Int {
    return pieces.index(after: i)
  }

  public subscript(_ index: Int) -> TriviaPiece {
    return pieces[index]
  }
}


extension Trivia: ExpressibleByArrayLiteral {
  /// Creates Trivia from the provided pieces.
  public init(arrayLiteral elements: TriviaPiece...) {
    self.pieces = elements
  }
}

/// Concatenates two collections of `Trivia` into one collection.
public func + (lhs: Trivia, rhs: Trivia) -> Trivia {
  return Trivia(pieces: lhs.pieces + rhs.pieces)
}
