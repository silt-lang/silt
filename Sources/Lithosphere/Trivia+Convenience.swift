/// Trivia+Convenience.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

extension TriviaPiece {
    /// Attempts to combine this trivia piece with the provided piece, or
    /// returns nil if both trivia cannot be combined into a single piece.
    /// For example, `.spaces(2).combined(with: .spaces(1))` is `.spaces(3)`.
    /// This can be used to incrementally build-up trivia.
    ///
    /// - Parameter piece: The piece you're trying to combine the receiver.
    /// - Returns: The result of combining two trivia pieces, or `nil` if they
    ///            are not of the same base type.
    public func combined(with piece: TriviaPiece) -> TriviaPiece? {
        switch (self, piece) {
        case let (.spaces(s1), .spaces(s2)):
            return .spaces(s1 + s2)
        case let (.tabs(s1), .tabs(s2)):
            return .tabs(s1 + s2)
        case let (.newlines(s1), .newlines(s2)):
            return .newlines(s1 + s2)
        default: return nil
        }
    }

    /// The total number of characters this trivia piece represents.
    public var length: Int {
        switch self {
        case .spaces(let n), .tabs(let n), .newlines(let n),
             .verticalTabs(let n), .formfeeds(let n):
            return n
        case .comment(let s):
            return s.count
        }
    }
}

extension Trivia {
    /// Appends a piece of trivia to this trivia, combining the pieces if
    /// necessary.
    public mutating func append(_ piece: TriviaPiece) {
        guard let last = pieces.last,
            let combined = last.combined(with: piece) else {
                pieces.append(piece)
                return
        }
        pieces[pieces.count - 1] = combined
    }

    /// The length, in characters, of this trivia piece.
    public var length: Int {
        return pieces.reduce(0) { $0 + $1.length }
    }

    public var containsWhitespace: Bool {
        for piece in pieces {
            if case .spaces = piece { return true }
            if case .tabs = piece { return true }
            if case .newlines = piece { return true }
        }
        return false
    }
}
