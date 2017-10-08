public class Syntax {
  let root: SyntaxData
  unowned let data: SyntaxData

  public class var kind: SyntaxKind {
    return .unknown
  }

  public required init(root: SyntaxData, data: SyntaxData) {
    self.root = root
    self.data = data
  }

  public var kind: SyntaxKind {
    return raw.kind
  }

  public var raw: RawSyntax {
    return data.raw
  }

  public var isMissing: Bool {
    return raw.presence == .missing
  }

  public var isImplicit: Bool {
    return raw.presence == .missing
  }

  public var isPresent: Bool {
    return raw.presence == .present
  }

  public var numberOfChildren: Int {
    return raw.layout.count
  }

  public var children: SyntaxChildren {
    return SyntaxChildren(node: self)
  }

  public func child<CursorType: RawRepresentable>(at cursor: CursorType) -> Syntax?
    where CursorType.RawValue == Int {
      return child(at: cursor.rawValue)
  }

  public func child(at index: Int) -> Syntax? {
    guard raw.layout.indices.contains(index) else { return nil }
    return raw.layout[index].makeSyntax(root: root,
                                        indexInParent: index,
                                        parent: data)
  }

  public var sourceText: String {
    return raw.sourceText
  }

  public var sourceRange: SourceRange? {
    return raw.sourceRange
  }
}
