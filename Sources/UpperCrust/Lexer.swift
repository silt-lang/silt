/// Lexer.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Foundation

extension Character {
  var isWhitespace: Bool {
    return self == " " || self == "\n" || self == "\t"
  }
}

public class Lexer {
  let input: String
  var index: String.Index
  var sourceLoc: SourceLocation

  public init(input: String, filePath: String) {
    self.input = input
    self.index = input.startIndex
    self.sourceLoc = SourceLocation(line: 1, column: 1,
                                    file: filePath,
                                    offset: 0)
  }

  func advance() {
    if let char = peek() {
      if char == "\n" {
        sourceLoc.line += 1
        sourceLoc.column = 0
      } else {
        sourceLoc.column += 1
      }
      sourceLoc.offset += 1
    }
    if index < input.endIndex {
      input.formIndex(after: &index)
    }
  }

  func peek(ahead n: Int = 0) -> Character? {
    guard let idx = input.index(index, offsetBy: n, limitedBy: input.endIndex) else {
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

  func collectBlockComment() -> String {
    var comment = "{-"
    advance()
    advance()
    while let char = peek(), let next = peek(ahead: 1) {
      // End of the comment */
      if char == "-" && next == "}" {
        comment += "-}"
        advance()
        advance()
        break
        // Beginning of a nested comment
      } else if char == "{" && next == "-" {
        comment += collectBlockComment()
        // Any other character
      } else {
        comment.append(char)
        advance()
      }
    }
    return comment
  }

  // Collects all trivia ahead of the current
  func collectTrivia(includeNewlines: Bool) -> Trivia {
    var trivia: Trivia = []
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
      case "-":
        if peek(ahead: 1) == "-" {
          trivia.append(.lineComment(collectLineComment()))
        } else {
          return trivia
        }
      case "{":
        if peek(ahead: 1) == "-" {
          trivia.append(.blockComment(collectBlockComment()))
        } else {
          return trivia
        }
      default:
        return trivia
      }
    }
    return trivia
  }

  func range(start: SourceLocation) -> SourceRange {
    return SourceRange(start: start, end: sourceLoc)
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
    let startLoc = sourceLoc

    let tokenKind: TokenKind
    guard let char = peek() else {
      return TokenSyntax(.eof, leadingTrivia: leadingTrivia,
                         sourceRange: range(start: startLoc))
    }

    let singleTokMap: [Character: TokenKind] = [
      "{": .leftBrace, "}": .rightBrace,
      "(": .leftParen, ")": .rightParen,
      "=": .equals, "\\": .forwardSlash,
      ".": .period, ":": .colon
    ]

    if let kind = singleTokMap[char] {
      tokenKind = kind
      advance()
    } else {
      let id = collectWhile { !$0.isWhitespace && singleTokMap[$0] == nil }
      tokenKind = TokenKind(identifier: id)
    }

    let trailingTrivia = collectTrivia(includeNewlines: false)

    return TokenSyntax(tokenKind, leadingTrivia: leadingTrivia,
                       trailingTrivia: trailingTrivia,
                       sourceRange: range(start: startLoc))
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
