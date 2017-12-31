/// Parser.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Lithosphere

private enum LayoutBlock {
  case implicit(TokenSyntax)
  case explicit(TokenSyntax)

  var isImplicit: Bool {
    switch self {
    case .implicit(_): return true
    default: return false
    }
  }
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
    guard self.sequence.count < other.sequence.count else {
      return false
    }

    for (l, r) in zip(self.sequence, other.sequence) {
      guard l == r else {
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
public func layout(_ ts: [TokenSyntax]) -> [TokenSyntax] {
  var toks = ts
  if toks.isEmpty {
    toks.append(TokenSyntax(.eof, presence: .implicit))
  }

  var stainlessToks = [TokenSyntax]()
  var layoutBlockStack = [WhitespaceSummary]()
  while toks[0].tokenKind != .eof {
    let tok = toks.removeFirst()
    let peekTok = toks[0]

    let ws = WhitespaceSummary(tok.leadingTrivia)
    guard tok.tokenKind != .whereKeyword else {
      stainlessToks.append(tok)

      let wsp = WhitespaceSummary(peekTok.leadingTrivia)

      if ws.equivalentTo(wsp) && !layoutBlockStack.isEmpty {
        stainlessToks.append(TokenSyntax(.leftBrace, leadingTrivia: .spaces(1),
                                         presence: .implicit))
        stainlessToks.append(TokenSyntax(.rightBrace, leadingTrivia: .spaces(1),
                                         presence: .implicit))
        continue
      } else {
        while let block = layoutBlockStack.last, !block.lessThan(wsp) {
          _ = layoutBlockStack.popLast()
          if !layoutBlockStack.isEmpty {
            stainlessToks.append(TokenSyntax(.rightBrace,
                                             leadingTrivia: .newlines(1),
                                             presence: .implicit))
            stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
          }
        }

        if layoutBlockStack.isEmpty {
          layoutBlockStack.append(wsp)
        } else if let block = layoutBlockStack.last, !wsp.equivalentTo(block) {
          // If we must, begin a new layout block
          layoutBlockStack.append(wsp)
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

    if ws.hasNewline, let lastBlock = layoutBlockStack.last {
      if ws.equivalentTo(lastBlock) {
        stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
      } else if ws.lessThan(lastBlock) {
        stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
        while let block = layoutBlockStack.last, ws.lessThan(block) {
          _ = layoutBlockStack.popLast()
          if !layoutBlockStack.isEmpty {
            stainlessToks.append(TokenSyntax(.rightBrace,
                                             leadingTrivia: .newlines(1),
                                             presence: .implicit))
            stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
          }
        }

        if let block = layoutBlockStack.last, !ws.equivalentTo(block) {
          // If we must, begin a new layout block
          layoutBlockStack.append(ws)
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
