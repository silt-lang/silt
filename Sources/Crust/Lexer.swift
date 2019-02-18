/// Lexer.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Lithosphere

extension Character {
  var isWhitespace: Bool {
    return self == " " || self == "\n" || self == "\t"
  }
}

public class Lexer {
  let input: String
  var index: String.Index

  public init(input: String, filePath: String) {
    self.input = input
    self.index = input.startIndex
  }

  func advance() {
    if index < input.endIndex {
      input.formIndex(after: &index)
    }
  }

  func peek(ahead n: Int = 0) -> Character? {
    guard let idx = input.index(index, offsetBy: n,
                                limitedBy: input.endIndex) else {
      return nil
    }
    if idx == input.endIndex { return nil }
    return input[idx]
  }

  func collectLineComment() -> String {
    var comment = "--"
    advance()
    advance()
    while let char = peek(), char != "\n" {
      comment.append(char)
      advance()
    }
    return comment
  }

  // Collects all trivia ahead of the current
  func collectTrivia(includeNewlines: Bool) -> Trivia {
    var trivia = [TriviaPiece]()
    while let char = peek() {
      switch char {
      case " ":
        trivia.append(.spaces(1))
        advance()
      case "\t":
        trivia.append(.tabs(1))
        advance()
      case "\n" where includeNewlines:
        trivia.append(.newlines(1))
        advance()
      case "\r":
        trivia.append(.carriageReturns(1))
        advance()
      case "-":
        if peek(ahead: 1) == "-" {
          trivia.append(.comment(collectLineComment()))
        } else {
          return Trivia(pieces: trivia)
        }
      default:
        return Trivia(pieces: trivia)
      }
    }
    return Trivia(pieces: trivia)
  }

  func collectWhile(_ shouldCollect: (Character) -> Bool) -> String {
    var text = ""
    while let char = peek(), shouldCollect(char) {
      text.append(char)
      advance()
    }
    return text
  }

  func nextToken() -> TokenSyntax {
    let leadingTrivia = collectTrivia(includeNewlines: true)

    let tokenKind: TokenKind
    guard let char = peek() else {
      return SyntaxFactory.makeToken(.eof, presence: .implicit,
                                     leadingTrivia: leadingTrivia)
    }

    let singleTokMap: [Character: TokenKind] = [
      "{": .leftBrace, "}": .rightBrace,
      "(": .leftParen, ")": .rightParen,
      "\\": .backSlash,
      ".": .period
    ]

    if let kind = singleTokMap[char] {
      tokenKind = kind
      advance()
    } else {
      let id = collectWhile { !$0.isWhitespace && singleTokMap[$0] == nil }
      tokenKind = TokenKind(text: id)
    }

    let trailingTrivia = collectTrivia(includeNewlines: false)
    
    return SyntaxFactory.makeToken(tokenKind, presence: .present,
                                   leadingTrivia: leadingTrivia,
                                   trailingTrivia: trailingTrivia)
  }

  public func tokenize() -> [TokenSyntax] {
    var toks = [TokenSyntax]()
    var token: TokenSyntax
    repeat {
      token = nextToken()
      toks.append(token)
      if case .eof = token.tokenKind { break }
    } while true
    return toks
  }
}
