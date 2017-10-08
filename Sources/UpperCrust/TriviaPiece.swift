/// A TriviaPiece is a piece of 'Trivia', or a non-semantic character like
/// spaces, tabs, newlines, or comments.
public enum TriviaPiece {
  /// A series of contiguous ' ' characters.
  case spaces(Int)

  /// A series of contiguous '\t' characters.
  case tabs(Int)

  /// A series of contiguous '\n' characters.
  case newlines(Int)

  /// A single line comment, marked by '//'
  case lineComment(String)

  /// A potentially multi-line comment that begins with '/*' and ends with
  /// '*/'
  case blockComment(String)


  /// Attempts to combine this trivia piece with the provided piece, or
  /// returns nil if both trivia cannot be combined into a single piece.
  /// For example, `.spaces(2).combined(with: .spaces(1))` is `.spaces(3)`.
  /// This can be used to incrementally build-up trivia.
  ///
  /// - Parameter piece: The piece you're trying to combine the receiver.
  /// - Returns: The result of combining two trivia pieces, or `nil` if they
  ///            are not of the same base type.
  public func combined(with piece: TriviaPiece) -> TriviaPiece? {
    switch (self, piece) {
    case let (.spaces(s1), .spaces(s2)):
      return .spaces(s1 + s2)
    case let (.tabs(s1), .tabs(s2)):
      return .tabs(s1 + s2)
    case let (.newlines(s1), .newlines(s2)):
      return .newlines(s1 + s2)
    default: return nil
    }
  }

  public var text: String {
    switch self {
    case .spaces(let n): return String(repeating: " ", count: n)
    case .tabs(let n): return String(repeating: "\t", count: n)
    case .newlines(let n): return String(repeating: "\n", count: n)
    case .lineComment(let s): return s
    case .blockComment(let s): return s
    }
  }

  /// The total number of characters this trivia piece represents.
  public var length: Int {
    switch self {
    case .spaces(let n), .tabs(let n), .newlines(let n):
      return n
    case .blockComment(let s), .lineComment(let s):
      return s.count
    }
  }
}
