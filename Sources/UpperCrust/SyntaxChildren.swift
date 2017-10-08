/// A sequence over the children of a Syntax node.
public struct SyntaxChildren: Sequence {
  let node: Syntax

  public func makeIterator() -> AnyIterator<Syntax> {
    var index = 0
    return AnyIterator {
      defer { index += 1 }
      return self.node.child(at: index)
    }
  }
}

extension SyntaxChildren: Collection {
  public subscript(_ index: Int) -> Syntax {
    guard let child = node.child(at: index) else {
      fatalError("index \(index) out of bounds for node with \(node.numberOfChildren) children ")
    }
    return child
  }

  public var startIndex: Int {
    return 0
  }

  public var endIndex: Int {
    return node.raw.layout.count
  }

  public func index(after i: Int) -> Int {
    return i + 1
  }
}
