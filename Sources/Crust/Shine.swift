/// Parser.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Lithosphere

private enum LayoutBlock {
  case implicit(TokenSyntax)
  case explicit(TokenSyntax)

  var isImplicit : Bool {
    switch self {
    case .implicit(_): return true
    default: return false
    }
  }
}

fileprivate extension TokenSyntax {
  func hasEquivalentLeadingWhitespace(to other: TokenSyntax) -> Bool {
    let selftrivia = self.leadingTrivia.filter({ if case .comment(_) = $0 { return false }; return true })
    let othertrivia = other.leadingTrivia.filter({ if case .comment(_) = $0 { return false }; return true })
    guard selftrivia.count == othertrivia.count else {
      return false
    }
    
    for (l, r) in zip(selftrivia.reversed(), othertrivia.reversed()) {
      switch (l, r) {
      // Search ends at the nearest newline.
      case (.newlines(_), .newlines(_)):
        return true
      // Obvious mismatches between spaces and tabs
      case (.spaces(_), .tabs(_)):
        return false
      case (.tabs(_), .spaces(_)):
        return false
      case (.spaces(let ln), .spaces(let rn)) where ln != rn:
        return false
      case (.tabs(let ln), .tabs(let rn)) where ln != rn:
        return false
      // Otherwise we have equal numbers of spaces or tabs
      case (.spaces(_), .spaces(_)):
        continue
      case (.tabs(_), .tabs(_)):
        continue
      // Keep searching
      default:
        continue
      }
    }
    return true
  }
}

/// Process a raw Silt token stream into a Stainless Silt token stream by
/// inserting layout markers in the appropriate places.  This ensures that we
/// have an explicitly-scoped input to the Parser before we even try to do a
/// Scope Check.
public func layout(_ ts : [TokenSyntax]) -> [TokenSyntax] {
  var toks = ts
  if toks.isEmpty {
    toks.append(TokenSyntax(.eof))
  }

  var lastLineLeader = toks.first!
  var stainlessToks = [TokenSyntax]()
  var layoutBlockStack = [LayoutBlock]()
  while toks[0].tokenKind != .eof {
    // Pop the first token in the stream
    let tok = toks.removeFirst()

    // If we've got a layout word, check to see if we need to push a new
    // layout block
    if tok.tokenKind == .whereKeyword || tok.tokenKind == .fieldKeyword {
      stainlessToks.append(tok)

      guard let peekTok = toks.first else {
        // If there's nothing after the layout word, open an implicit block and
        // append a brace into the token stream.
        layoutBlockStack.append(.implicit(lastLineLeader))
        stainlessToks.append(TokenSyntax(.leftBrace, leadingTrivia: .spaces(1),
                                         presence: .implicit))
        continue
      }

      if peekTok.tokenKind == .leftBrace {
        layoutBlockStack.append(.explicit(lastLineLeader))
      } else {
        lastLineLeader = peekTok
        layoutBlockStack.append(.implicit(lastLineLeader))
        stainlessToks.append(TokenSyntax(.leftBrace, leadingTrivia: .spaces(1),
                                         presence: .implicit))
      }
      continue
    }

    // If we find a left brace, push an explicit block onto the layout stack
    if tok.tokenKind == .leftBrace {
      layoutBlockStack.append(.explicit(lastLineLeader))
      stainlessToks.append(tok)
      continue
    }

    // Next, check to see if we have a closing brace to match anything on
    // the layout stack
    if tok.tokenKind == .rightBrace {
      // If we're inside an implicit layout block but see an explicit closer,
      // we need to pop off as many implicit layout blocks as it takes to
      // find the matching explicit layout block
      assert(!layoutBlockStack.isEmpty,
             """
             Empty layout stack encountered while trying to match explicit '}' \
             at \(tok.sourceRange as Optional)
             """)
      var foundExplicit = false
      while let implTop = layoutBlockStack.popLast() {
        if case let .implicit(lll) = implTop {
          stainlessToks.append(TokenSyntax(.rightBrace,
                                           leadingTrivia: .newlines(1),
                                           presence: .implicit))
          stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
          lastLineLeader = lll
        } else if case let .explicit(lll) = implTop {
          foundExplicit = true
          lastLineLeader = lll
          break
        }
      }
      assert(foundExplicit,
             """
             Empty layout stack encountered while trying to match explicit '}' \
             at \(tok.sourceRange as Optional)
             """)
    }

    stainlessToks.append(tok)

    // Finally, check to see if we've got a token on a new line at the same indent
    // level.  If so, we need to insert a semicolon in the token stream if we
    // can't find one.
    //
    // FIXME: This seems wrong in general.
    func newlineAmongTrivia(_ t : Trivia) -> Bool {
      return t.reduce(false, { (acc, n) in
        switch n {
        case .newlines(_): return true
        default: return acc
        }
      })
    }

    if
      let peekTok = toks.first,
      peekTok.tokenKind != .semicolon,
      newlineAmongTrivia(peekTok.leadingTrivia),
      peekTok.hasEquivalentLeadingWhitespace(to: lastLineLeader)
    {
      stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
      lastLineLeader = peekTok
    }
  }

  // If we're out of tokens to process, cleanup the implicit layout stack with
  // closing braces.
  while let lb = layoutBlockStack.popLast() {
    switch lb {
    case .implicit:
      stainlessToks.append(TokenSyntax(.rightBrace, leadingTrivia: .newlines(1),
                                       presence: .implicit))
      stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
    case .explicit: ()
    }
  }

  // Append the EOF on the way out
  guard let lastTok = toks.last, case .eof = lastTok.tokenKind else {
    fatalError("Did not find EOF as the last token?")
  }
  stainlessToks.append(lastTok)

  return stainlessToks
}
