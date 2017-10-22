/// Parser.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Lithosphere

private enum LayoutBlock {
  case implicit
  case explicit

  var isImplicit : Bool {
    switch self {
    case .implicit: return true
    default: return false
    }
  }
}

/// Process a raw Silt token stream into a Stainless Silt token stream by
/// inserting layout markers in the appropriate places.  This ensures that we
/// have an explicitly-scoped input to the Parser before we even try to do a
/// Scope Check.
public func layout(_ ts : [TokenSyntax]) -> [TokenSyntax] {
  var toks = ts
  var stainlessToks = [TokenSyntax]()
  var layoutBlockStack = [LayoutBlock]()
  while !toks.isEmpty && toks[0].tokenKind != .eof {
    // Pop the first token in the stream
    let tok = toks.removeFirst()

    // If we've got a layout word, check to see if we need to push a new
    // layout block
    if tok.tokenKind == .whereKeyword || tok.tokenKind == .fieldKeyword {
      stainlessToks.append(tok)

      guard let peekTok = toks.first else {
        // If there's nothing after the layout word, open an implicit block and
        // append a brace into the token stream.
        layoutBlockStack.append(.implicit)
        stainlessToks.append(TokenSyntax(.leftBrace, leadingTrivia: .spaces(1),
                                         presence: .implicit))
        continue
      }

      if peekTok.tokenKind == .leftBrace {
        layoutBlockStack.append(.explicit)
      } else {
        layoutBlockStack.append(.implicit)
        stainlessToks.append(TokenSyntax(.leftBrace, leadingTrivia: .spaces(1),
                                         presence: .implicit))
      }
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
        switch implTop {
        case .implicit:
          stainlessToks.append(TokenSyntax(.rightBrace,
                                           leadingTrivia: .newlines(1),
                                           presence: .implicit))
        case .explicit:
          foundExplicit = true
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

    // Finally, check to see if we've got a token on a new line.  If so, we
    // need to insert a semicolon in the token stream if we can't find one.
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
      newlineAmongTrivia(peekTok.leadingTrivia)
    {
      stainlessToks.append(TokenSyntax(.semicolon, presence: .implicit))
    }
  }

  // If we're out of tokens to process, cleanup the implicit layout stack with
  // closing braces.
  while let lb = layoutBlockStack.popLast() {
    switch lb {
    case .implicit:
      stainlessToks.append(TokenSyntax(.rightBrace, leadingTrivia: .newlines(1),
                                       presence: .implicit))
    case .explicit: ()
    }
  }

  // Append the EOF on the way out
  if let lastTok = toks.last, case .eof = lastTok.tokenKind {
    stainlessToks.append(lastTok)
  } else {
    stainlessToks.append(TokenSyntax(.eof))
  }
  return stainlessToks
}
