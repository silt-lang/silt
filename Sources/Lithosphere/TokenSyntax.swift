/// TokenSyntax.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

public class TokenSyntax: Syntax {
  public convenience init(_ kind: TokenKind, leadingTrivia: Trivia = [],
                          trailingTrivia: Trivia = [],
                          presence: SourcePresence = .present,
                          sourceRange: SourceRange? = nil) {
    let raw = RawSyntax.token(kind, leadingTrivia, trailingTrivia,
                              presence, sourceRange)
    let data = SyntaxData(raw: raw, indexInParent: 0, parent: nil)
    self.init(root: data, data: data)
  }

  public var sourceRange: SourceRange? {
    guard case let .token(_, _, _, _, sourceRange) = raw else {
      fatalError("non-token TokenSyntax?")
    }
    return sourceRange
  }

  public var tokenKind: TokenKind {
    guard case let .token(kind, _, _, _, _) = raw else {
      fatalError("non-token TokenSyntax?")
    }
    return kind
  }

  public func withTokenKind(_ kind: TokenKind) -> TokenSyntax {
    guard case let .token(_, leadingTrivia, trailingTrivia,
                          presence, range) = raw else {
      fatalError("non-token TokenSyntax?")
    }
    let (newRoot, newData) =
      data.replacingSelf(.token(kind, leadingTrivia,
                                trailingTrivia, presence, range))
    return TokenSyntax(root: newRoot, data: newData)
  }

  public var leadingTrivia: Trivia {
    guard case let .token(_, leadingTrivia, _, _, _) = raw else {
      fatalError("non-token TokenSyntax?")
    }
    return leadingTrivia
  }

  public func withLeadingTrivia(_ leadingTrivia: Trivia) -> TokenSyntax {
    guard case let .token(kind, _, trailingTrivia, presence, range) = raw else {
      fatalError("non-token TokenSyntax?")
    }
    let (newRoot, newData) =
      data.replacingSelf(.token(kind, leadingTrivia,
                                trailingTrivia, presence, range))
    return TokenSyntax(root: newRoot, data: newData)
  }

  public var trailingTrivia: Trivia {
    guard case let .token(_, _, trailingTrivia, _, _) = raw else {
      fatalError("non-token TokenSyntax?")
    }
    return trailingTrivia
  }

  public func withTrailingTrivia(_ trailingTrivia: Trivia) -> TokenSyntax {
    guard case let .token(kind, leadingTrivia, _, presence, range) = raw else {
      fatalError("non-token TokenSyntax?")
    }
    let (newRoot, newData) =
      data.replacingSelf(.token(kind, leadingTrivia,
                                trailingTrivia, presence, range))
    return TokenSyntax(root: newRoot, data: newData)
  }
}
