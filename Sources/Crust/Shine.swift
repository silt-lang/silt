/// Parser.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Lithosphere

enum LayoutBlockSource {
  case letKeyword
  case whereKeyword
}

struct WhitespaceSummary {
  enum Spacer: Equatable {
    case spaces(Int)
    case tabs(Int)

    static func == (lhs: Spacer, rhs: Spacer) -> Bool {
      switch (lhs, rhs) {
      case let (.spaces(l), .spaces(r)): return l == r
      case let (.tabs(l), .tabs(r)): return l == r
      default: return false
      }
    }

    static func < (lhs: Spacer, rhs: Spacer) -> Bool {
      switch (lhs, rhs) {
      case let (.spaces(l), .spaces(r)): return l < r
      case let (.tabs(l), .tabs(r)): return l < r
      default: return false
      }
    }

    static func <= (lhs: Spacer, rhs: Spacer) -> Bool {
      switch (lhs, rhs) {
      case let (.spaces(l), .spaces(r)): return l <= r
      case let (.tabs(l), .tabs(r)): return l <= r
      default: return false
      }
    }
  }

  func asTrivia(_ newline: Bool) -> Trivia {
    var trivia: Trivia = newline ? .newlines(1) : []
    for val in self.sequence {
      switch val {
      case let .spaces(n):
        trivia.append(.spaces(n))
      case let .tabs(n):
        trivia.append(.tabs(n))
      }
    }
    return trivia
  }

  let sequence: [Spacer]
  let totals: (Int, Int)
  let hasNewline: Bool

  init(_ t: Trivia) {
    var seq = [Spacer]()
    var spaces = 0
    var tabs = 0
    var newl = false
    for i in (0..<t.count).reversed() {
      switch t[i] {
      case .spaces(let ss):
        spaces += ss
        seq.append(.spaces(ss))
        continue
      case .tabs(let ts):
        tabs += ts
        seq.append(.tabs(ts))
        continue
      case .comment(_):
        continue
      default:
        newl = true
      }
      break
    }
    self.sequence = seq
    self.totals = (spaces, tabs)
    self.hasNewline = newl
  }

  func equivalentTo(_ other: WhitespaceSummary) -> Bool {
    guard self.sequence.count == other.sequence.count else {
      return false
    }

    guard self.totals == other.totals else {
      return false
    }
    return true
  }

  func equalTo(_ other: WhitespaceSummary) -> Bool {
    guard self.equivalentTo(other) else {
      return false
    }

    for (l, r) in zip(self.sequence, other.sequence) {
      guard l == r else {
        return false
      }
    }

    return true
  }

  func lessThan(_ other: WhitespaceSummary) -> Bool {
    guard self.sequence.count <= other.sequence.count else {
      return false
    }

    for (l, r) in zip(self.sequence, other.sequence) {
      guard l < r else {
        return false
      }
    }

    return true
  }

  func lessThanOrEqual(_ other: WhitespaceSummary) -> Bool {
    guard self.sequence.count <= other.sequence.count else {
      return false
    }

    for (l, r) in zip(self.sequence, other.sequence) {
      guard l <= r else {
        return false
      }
    }

    return true
  }

  var totalWhitespaceCount: Int { return self.totals.0 + self.totals.1 }
}

fileprivate extension TokenSyntax {
  func hasEquivalentLeadingWhitespace(to other: TokenSyntax) -> Bool {
    guard WhitespaceSummary(self.leadingTrivia)
            .equalTo(WhitespaceSummary(other.leadingTrivia)) else {
      return false
    }

    return true
  }
}

/// Process a raw Silt token stream into a Stainless Silt token stream by
/// inserting layout markers in the appropriate places.  This ensures that we
/// have an explicitly-scoped input to the Parser before we even try to do a
/// Scope Check.
public func dumpToks(_ toks: [TokenSyntax]) {
  for tok in toks {
    print(tok.shinedSourceText, terminator: "")
  }
}

public func layout(_ ts: [TokenSyntax]) -> [TokenSyntax] {
  var toks = ts
  if toks.isEmpty {
    toks.append(TokenSyntax(.eof, presence: .implicit))
  }

  var stainlessToks = [TokenSyntax]()
  var layoutBlockStack = [(LayoutBlockSource, WhitespaceSummary)]()
  while toks[0].tokenKind != .eof {
    let tok = toks.removeFirst()
    let peekTok = toks[0]

    let wsp = WhitespaceSummary(peekTok.leadingTrivia)
    let ws = WhitespaceSummary(tok.leadingTrivia)
    guard tok.tokenKind != .letKeyword else {
      stainlessToks.append(tok)
      layoutBlockStack.append((.letKeyword, wsp))
      stainlessToks.append(TokenSyntax(.leftBrace,
                                       leadingTrivia: .spaces(1),
                                       presence: .implicit))
      stainlessToks.append(toks.removeFirst())
      continue
    }

    guard tok.tokenKind != .inKeyword else {
      while let (src, block) = layoutBlockStack.last, src != .letKeyword {
        _ = layoutBlockStack.popLast()
        if !layoutBlockStack.isEmpty {
          stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
          stainlessToks.append(TokenSyntax(.rightBrace,
                                           leadingTrivia: block.asTrivia(true),
                                           presence: .implicit))
        }
      }
      stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
      stainlessToks.append(TokenSyntax(.rightBrace,
                                       leadingTrivia: .spaces(1),
                                       presence: .implicit))
      _ = layoutBlockStack.popLast()
      stainlessToks.append(tok)
      continue
    }


    guard tok.tokenKind != .whereKeyword else {
      stainlessToks.append(tok)

      if ws.equivalentTo(wsp) && !layoutBlockStack.isEmpty {
        stainlessToks.append(TokenSyntax(.leftBrace, leadingTrivia: .spaces(1),
                                         presence: .implicit))
        stainlessToks.append(TokenSyntax(.rightBrace, leadingTrivia: .spaces(1),
                                         presence: .implicit))
        continue
      } else {
        while
          let (_, block) = layoutBlockStack.last, !block.lessThanOrEqual(wsp) {
          _ = layoutBlockStack.popLast()
          if !layoutBlockStack.isEmpty {
            stainlessToks.append(TokenSyntax(.rightBrace,
                                             leadingTrivia: .newlines(1),
                                             presence: .implicit))
            stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
          }
        }

        if layoutBlockStack.isEmpty {
          layoutBlockStack.append((.whereKeyword, wsp))
        } else if
          let (_, block) = layoutBlockStack.last, !wsp.equivalentTo(block) {
          // If we must, begin a new layout block
          layoutBlockStack.append((.whereKeyword, wsp))
        }

        stainlessToks.append(TokenSyntax(.leftBrace, leadingTrivia: .spaces(1),
                                         presence: .implicit))
      }

      // Ignore the EOF
      guard peekTok.tokenKind != .eof  else {
        continue
      }
      stainlessToks.append(toks.removeFirst())
      continue
    }

    // If we've hit the end, push the token and bail.
    guard peekTok.tokenKind != .eof  else {
      stainlessToks.append(tok)
      break
    }

    if ws.hasNewline, let (_, lastBlock) = layoutBlockStack.last {
      if ws.equivalentTo(lastBlock) {
        stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
      } else if ws.lessThan(lastBlock) {
        stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
        while
          let (_, block) = layoutBlockStack.last, !block.lessThanOrEqual(ws) {
          _ = layoutBlockStack.popLast()
          if !layoutBlockStack.isEmpty {
            stainlessToks.append(TokenSyntax(.rightBrace,
                                             leadingTrivia: .newlines(1),
                                             presence: .implicit))
            stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
          }
        }

        if let (_, block) = layoutBlockStack.last, !ws.equivalentTo(block) {
          // If we must, begin a new layout block
          layoutBlockStack.append((.whereKeyword, ws))
        }
      }
    }

    stainlessToks.append(tok)
  }

  while let _ = layoutBlockStack.popLast() {
    stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
    stainlessToks.append(TokenSyntax(.rightBrace,
                                     leadingTrivia: .newlines(1),
                                     presence: .implicit))
  }
  stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))

  // Append the EOF on the way out
  guard let lastTok = toks.last, case .eof = lastTok.tokenKind else {
    fatalError("Did not find EOF as the last token?")
  }
  stainlessToks.append(lastTok)

  return stainlessToks
}
