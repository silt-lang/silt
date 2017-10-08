public indirect enum RawSyntax {
  case node(SyntaxKind, [RawSyntax], SourcePresence)
  case token(TokenKind, Trivia, Trivia, SourcePresence, SourceRange?)

  static func missing(_ kind: SyntaxKind) -> RawSyntax {
    return .node(kind, [], .missing)
  }

  static func missingToken(_ kind: TokenKind) -> RawSyntax {
    return .token(kind, [], [], .missing, nil)
  }

  var sourceText: String {
    var s = ""
    print(to: &s)
    return s
  }

  var layout: [RawSyntax] {
    switch self {
    case .node(_, let children, _): return children
    case .token(_, _, _, _, _): return []
    }
  }

  var sourceRange: SourceRange? {
    switch self {
    case .node(_, _, .missing): return nil
    case .node(_, let children, _):
      var start: SourceLocation?
      var end: SourceLocation?
      for child in children {
        if start == nil, let range = child.sourceRange {
          start = range.start
          break
        }
      }
      for child in children.reversed() {
        if end == nil, let range = child.sourceRange {
          end = range.end
          break
        }
      }
      guard let _start = start, let _end = end else { return nil }
      return SourceRange(start: _start, end: _end)
    case .token(_, _, _, _, let range): return range
    }
  }

  var kind: SyntaxKind {
    switch self {
    case .node(let kind, _, _): return kind
    case .token(_, _, _, _, _): return .token
    }
  }

  var presence: SourcePresence {
    switch self {
    case let .node(_, _, presence): return presence
    case let .token(_, _, _, presence, _): return presence
    }
  }

  /// Creates a Syntax node from this RawSyntax using the appropriate Syntax
  /// type, as specified by its kind.
  func makeRootSyntax() -> Syntax {
    return makeSyntax(root: nil, indexInParent: 0, parent: nil)
  }

  /// Creates a Syntax node from this RawSyntax using the appropriate Syntax
  /// type, as specified by its kind.
  /// - Parameters:
  ///   - root: The root of this tree, or `nil` if the new node is the root.
  ///   - indexInParent: The index of this node in the parent. Ignored if
  ///                    the parent provided is `nil`.
  ///   - parent: The parent data for this new node, or `nil` if this node is
  ///             the root.
  func makeSyntax(root: SyntaxData?, indexInParent: Int,
                  parent: SyntaxData?) -> Syntax {
    let data = parent?.cachedChild(at: indexInParent) ??
      SyntaxData(raw: self, parent: parent,
                 indexInParent: indexInParent)
    return kind.syntaxType.init(root: root ?? data, data: data)
  }

  func replacingChild(_ index: Int, with child: RawSyntax) -> RawSyntax {
    guard case let .node(kind, layout, presence) = self else { return self }
    var newLayout = layout
    newLayout[index] = child
    return .node(kind, newLayout, presence)
  }
  
  func print<StreamType: TextOutputStream>(to stream: inout StreamType) {
    switch self {
    case let .node(_, children, _):
      for child in children {
        child.print(to: &stream)
      }
    case let .token(kind, leadingTrivia, trailingTrivia, presence, _):
      guard presence != .missing else { return }
      leadingTrivia.print(to: &stream)
      stream.write(kind.text)
      trailingTrivia.print(to: &stream)
    }
  }
}
