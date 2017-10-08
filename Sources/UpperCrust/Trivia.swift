/// A collection of trivia pieces either before or after a token.
public struct Trivia {
  /// The underlying pieces that make up this trivia.
  public private(set) var pieces: [TriviaPiece]
  
  /// Appends a piece of trivia to this trivia, combining the pieces if
  /// necessary.
  public mutating func append(_ piece: TriviaPiece) {
    guard let last = pieces.last,
      let combined = last.combined(with: piece) else {
        pieces.append(piece)
        return
    }
    pieces[pieces.count - 1] = combined
  }
  
  /// The length, in characters, of this trivia piece.
  public var length: Int {
    return pieces.reduce(0) { $0 + $1.length }
  }

  public var containsWhitespace: Bool {
    for piece in pieces {
      if case .spaces = piece { return true }
      if case .tabs = piece { return true }
      if case .newlines = piece { return true }
    }
    return false
  }
  
  public func print<StreamType: TextOutputStream>(to stream: inout StreamType) {
    for piece in pieces {
      stream.write(piece.text)
    }
  }
}

extension Trivia: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: TriviaPiece...) {
    self = Trivia(pieces: elements)
  }
}
