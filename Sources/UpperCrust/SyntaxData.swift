public  class SyntaxData {
  let raw: RawSyntax
  private weak var parent: SyntaxData?
  let indexInParent: Int

  private let childCaches: [AtomicCache<SyntaxData>]

  public  init(raw: RawSyntax, parent: SyntaxData?, indexInParent: Int) {
    self.raw = raw
    self.parent = parent
    self.indexInParent = indexInParent
    self.childCaches = raw.layout.map { _ in AtomicCache() }
  }

  /// Creates a copy of `self` and recursively creates `SyntaxData` nodes up to
  /// the root.
  /// - parameter newRaw: The new RawSyntax that will back the new `Data`
  /// - returns: A Syntax node with the provided `RawSyntax` backing it.
  public func replacingSelf<SyntaxType: Syntax>(_ newRaw: RawSyntax) -> SyntaxType {
    let (root, data) = replacingSelf(newRaw)
    return SyntaxType.init(root: root, data: data)
  }

  /// Creates a copy of `self` and recursively creates `SyntaxData` nodes up to
  /// the root.
  /// - parameter newRaw: The new RawSyntax that will back the new `Data`
  /// - returns: A tuple of both the new root node and the new data with the raw
  ///            layout replaced.
  public func replacingSelf(_ newRaw: RawSyntax) -> (root: SyntaxData, newValue: SyntaxData) {
    // If we have a parent already, then ask our current parent to copy itself
    // recursively up to the root.
    if let parent = parent {
      let (root, newParent) = parent.replacingChild(newRaw, at: indexInParent)
      let newMe = newParent.cachedChild(at: indexInParent)
      return (root: root, newValue: newMe)
    } else {
      // Otherwise, we're already the root, so return the new data as both the
      // new root and the new data.
      let newMe = SyntaxData(raw: newRaw, parent: nil,
                             indexInParent: indexInParent)
      return (root: newMe, newValue: newMe)
    }
  }

  /// Creates a copy of `self` with the child at the provided index replaced
  /// with a new SyntaxData containing the raw syntax provided.
  ///
  /// - Parameters:
  ///   - child: The raw syntax for the new child to replace.
  ///   - index: The index pointing to where in the raw layout to place this
  ///            child.
  /// - Returns: The new root node created by this operation, and the new child
  ///            syntax data.
  /// - SeeAlso: replacingSelf(_:)
  public func replacingChild(_ child: RawSyntax, at index: Int) -> (root: SyntaxData, newValue: SyntaxData) {
    let newRaw = raw.replacingChild(index, with: child)
    return replacingSelf(newRaw)
  }

  /// Creates a copy of `self` with the child at the provided cursor replaced
  /// with a new SyntaxData containing the raw syntax provided.
  ///
  /// - Parameters:
  ///   - child: The raw syntax for the new child to replace.
  ///   - cursor: The cursor pointing to where in the raw layout to place this
  ///             child.
  /// - Returns: A Syntax node of the appropriate type representing the child.
  public func replacingChild<CursorType: RawRepresentable, SyntaxType: Syntax>
    (_ child: RawSyntax, at cursor: CursorType) -> SyntaxType
    where CursorType.RawValue == Int {
      let (root, data) = replacingChild(child, at: cursor.rawValue)
      return SyntaxType.init(root: root, data: data)
  }

  /// Gets the child at the provided index in the parent's cached children
  /// array.
  func cachedChild(at index: Int) -> SyntaxData {
    return childCaches[index].value {
      SyntaxData(raw: raw.layout[index],
                 parent: self,
                 indexInParent: index)
    }
  }

  func cachedChild<CursorType: RawRepresentable>(at cursor: CursorType) -> SyntaxData
    where CursorType.RawValue == Int {
      return cachedChild(at: cursor.rawValue)
  }

}
