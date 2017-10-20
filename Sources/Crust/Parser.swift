/// Parser.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Lithosphere

enum ParseError: Error {
  case unexpectedToken(TokenSyntax)
  case unexpectedEOF
}

public class Parser {
  let tokens: [TokenSyntax]
  var index = 0

  public init(tokens: [TokenSyntax]) {
    self.tokens = tokens
  }

  var currentToken: TokenSyntax? {
    return index < tokens.count ? tokens[index] : nil
  }

  func consume(_ kinds: TokenKind...) throws -> TokenSyntax {
    guard let token = currentToken else {
      throw ParseError.unexpectedEOF
    }
    guard kinds.index(of: token.tokenKind) != nil else {
      throw ParseError.unexpectedToken(token)
    }
    advance()
    return token
  }

  func peek(ahead n: Int = 0) -> TokenKind {
    guard index + n < tokens.count else { return .eof }
    return tokens[index + n].tokenKind
  }

  func advance(_ n: Int = 1) {
    index += n
  }
}
