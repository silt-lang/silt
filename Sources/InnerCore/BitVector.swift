/// BitVector.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import LLVM

/// A `BitVector` is an ordered collection of bits.
public struct BitVector: Equatable, Collection {
  public typealias BitWord = UInt64

  public struct SetBitIterator: IteratorProtocol {
    private let bitvector: BitVector
    private var index: Int
    private let lastIndex: Int
    private var currentWord: BitWord

    fileprivate init(_ bitvector: BitVector) {
      self.bitvector = bitvector
      self.index = 0
      self.lastIndex = bitvector.isEmpty ? 0 : numBitWords(bitvector.bitCount)
      self.currentWord = bitvector.isEmpty ? 0 : bitvector.bitBuffer[0]
    }

    public mutating func next() -> Int? {
      guard self.index < self.lastIndex else {
        return nil
      }

      var cur = self.currentWord
      while cur == 0 {
        self.index += 1
        guard self.index < self.lastIndex else {
          return nil
        }
        cur = bitvector.bitBuffer[self.index]
      }

      // Find the index of the lowest set bit.
      let bitIndex = cur.trailingZeroBitCount

      // Clear that bit in the current chunk.
      self.currentWord = cur ^ (BitWord(1) << bitIndex)
      assert(self.currentWord & (BitWord(1) << bitIndex) == 0)

      return self.index * chunkSizeInBits + bitIndex
    }
  }

  /// The backing buffer for this bitvector.
  private var bitBuffer: [BitWord]
  /// The total number of valid bits in the bitBuffer.
  private var bitCount: Int

  /// Initializes a new, empty bit vector.
  public init() {
    self.bitBuffer = []
    self.bitCount = 0
  }

  /// The total number of bits in the bit vector.
  public var count: Int {
    return self.bitCount
  }

  /// A Boolean value indicating whether the collection is empty.
  public var isEmpty: Bool {
    return self.bitCount == 0
  }

  /// The total number of elements that the bit vector can contain without
  /// allocating new storage.
  public var capacity: Int {
    return self.bitBuffer.count * chunkSizeInBits
  }

  /// The position of the first bit in the bit vector.
  public var startIndex: Int {
    return 0
  }

  /// The position of the last bit in the bit vector.
  public var endIndex: Int {
    return self.count
  }

  /// Returns the position immediately after the given index.
  public func index(after i: Int) -> Int {
    return i + 1
  }

  /// Returns an iterator over the indices of the bits that are set in this
  /// bit vector.
  ///
  /// - note: This differs from the default iterator which iterates over all
  ///   bits in the bit vector, regardless of whether they are set of not.
  public func makeSetBitIterator() -> SetBitIterator {
    return SetBitIterator(self)
  }

  /// Retrieves the bit value at the given index.
  public subscript(position: Int) -> Bool {
    return self.testBit(at: position)
  }

  /// Computes the number of bits equal to 1 in the bit vector.
  public func nonzeroBitCount() -> Int {
    var bitCount = 0
    for i in 0..<numBitWords(self.bitCount) {
      bitCount += self.bitBuffer[i].nonzeroBitCount
    }
    return bitCount
  }

  /// Returns true if any bit is set in the bit vector.
  public func any() -> Bool {
    for i in 0..<numBitWords(self.bitCount) {
      guard self.bitBuffer[i] == 0 else {
        return true
      }
    }
    return false
  }

  /// Returns true if no bit is set in the bit vector.
  public func none() -> Bool {
    return !any()
  }

  /// Removes all elements from the bit vector.
  public mutating func removeAll() {
    self.bitCount = 0
  }

  /// Reserves enough space to store the specified number of elements.
  public mutating func reserveCapacity(_ minimumCapacity: Int) {
    guard minimumCapacity > self.bitBuffer.count * chunkSizeInBits else {
      return
    }
    self.grow(to: minimumCapacity)
  }

  /// Flips all of the bits in this bit vector.
  public mutating func flipAll() {
    for i in 0..<numBitWords(self.bitCount) {
      self.bitBuffer[i] = ~self.bitBuffer[i]
    }
    self.clearUnusedBits()
  }

  /// Flips the value of the bit at the given index.
  public mutating func flipBit(at index: Int) {
    let (chnkIdx, off) = index.quotientAndRemainder(dividingBy: chunkSizeInBits)

    self.bitBuffer[chnkIdx] ^= BitWord(1) << off
  }

  /// Returns the value of the bit at the given index.
  public func testBit(at index: Int) -> Bool {
    precondition(index < self.bitCount, "index out of bounds")
    let mask = BitWord(1) << (index % chunkSizeInBits)
    return (self.bitBuffer[index / chunkSizeInBits] & mask) != 0
  }

  public mutating func append(contentsOf other: BitVector) {
    guard !other.isEmpty else {
      return
    }

    self.reserveCapacity(self.bitCount + other.bitCount)
    appendReserved(other.bitCount, other.bitBuffer)
  }

  /// Add the low N bits from the given value to the vector.
  public mutating func append(bits numBits: Int, from value: BitWord) {
    assert(numBits <= MemoryLayout<BitWord>.size * CChar.bitWidth)
    guard numBits > 0 else {
      return
    }

    self.reserveCapacity(self.bitCount + numBits)
    appendReserved(numBits, [value])
  }

  /// Append a given number of clear bits to this vector.
  public mutating func appendClearBits(_ numBits: Int) {
    guard numBits > 0 else {
      return
    }

    self.reserveCapacity(self.bitCount + numBits)
    appendConstantBitsReserved(numBits, false)
  }

  /// Append a given number of set bits to this vector.
  public mutating func appendSetBits(_ numBits: Int) {
    guard numBits > 0 else {
      return
    }

    self.reserveCapacity(self.bitCount + numBits)
    appendConstantBitsReserved(numBits, true)
  }

  private mutating func grow(to newSize: Int) {
    let newCapacity = Swift.max(numBitWords(newSize), self.bitBuffer.count * 2)
    assert(newCapacity > 0, "realloc-ing zero space")
    self.bitBuffer += [BitWord](repeating: 0,
                                count: newCapacity - numBitWords(self.capacity))
    self.clearUnusedBits()
  }

  private mutating func clearUnusedBits() {
    let usedWords = numBitWords(self.bitCount)
    //  Set any stray high bits of the last used word.
    let extraBits = self.bitCount % chunkSizeInBits
    if extraBits != 0 {
      self.bitBuffer[usedWords - 1] &= (BitWord(1) << extraBits) - 1
    }

    guard self.bitBuffer.count > usedWords else {
      return
    }

    // Scrub the rest of the chunks.
    for chunkIdx in usedWords..<self.bitBuffer.endIndex {
      self.bitBuffer[chunkIdx] = 0
    }
  }

  private mutating func appendConstantBitsReserved(
    _ numBits: Int, _ addOnes: Bool
  ) {
    assert(self.bitCount + numBits <= self.capacity)
    assert(numBits > 0)

    let pattern = addOnes ? ~BitWord(0) : BitWord(0)
    appendGeneratedChunks(numBits) { (numBitsWanted) -> BitWord in
      return pattern >> (chunkSizeInBits - numBitsWanted)
    }
  }

  private mutating func appendReserved(_ numBits: Int, _ chunks: [BitWord]) {
    let extraBits = self.bitCount % chunkSizeInBits
    var chunkIndex = chunks.startIndex
    guard extraBits != 0 else {
      return self.appendGeneratedChunks(numBits) { _ -> BitWord in
        defer { chunkIndex += 1 }
        return chunks[chunkIndex]
      }
    }

    var prevChunk = BitWord(0)
    var bitsRemaining = 0
    return appendGeneratedChunks(numBits) { (numBitsWanted) -> BitWord in
      let resultMask: BitWord
      if numBitsWanted == chunkSizeInBits {
        resultMask = ~BitWord(0)
      } else {
        resultMask = (BitWord(1) << numBitsWanted) - 1
      }

      guard numBitsWanted > bitsRemaining else {
        assert(numBitsWanted != chunkSizeInBits)
        let result = prevChunk & resultMask
        bitsRemaining -= numBitsWanted
        prevChunk >>= numBitsWanted
        return result
      }

      let newChunk = chunks[chunkIndex]
      chunkIndex += 1
      let result = (prevChunk | (newChunk << bitsRemaining)) & resultMask
      prevChunk = newChunk >> (numBitsWanted - bitsRemaining)
      bitsRemaining = chunkSizeInBits + bitsRemaining - numBitsWanted
      return result
    }
  }

  private mutating func appendGeneratedChunks(
    _ numBits: Int, _ bitGenerator: (Int) -> BitWord) {
    assert(self.bitCount + numBits <= self.capacity)
    assert(numBits > 0)

    // Compute the index of the last chunk and whether we have extra bits in the
    // final chunk.
    var (chunkIdx, extraBits) =
        self.bitCount.quotientAndRemainder(dividingBy: chunkSizeInBits)

    // Up the bit count.
    self.bitCount += numBits

    // Extra bits the final chunk mean we need to OR into it.
    var numBits = numBits
    if extraBits != 0 {
      let claimedBits = Swift.min(numBits, chunkSizeInBits - extraBits)

      self.bitBuffer[chunkIdx] |= bitGenerator(claimedBits) << extraBits
      chunkIdx += 1

      numBits -= claimedBits
    }

    // After that, just drain into the subsequent chunks.
    while numBits != 0 {
      let claimedBits = Swift.min(numBits, chunkSizeInBits)
      self.bitBuffer[chunkIdx] = bitGenerator(claimedBits)
      chunkIdx += 1
      numBits -= claimedBits
    }
  }
}

extension BitVector {
  public static func == (_ lhs: BitVector, _ rhs: BitVector) -> Bool {
    let lhsWords = numBitWords(lhs.bitCount)
    let rhsWords  = numBitWords(rhs.bitCount)
    var i = 0
    while i < Swift.min(lhsWords, rhsWords) {
      defer { i += 1 }
      if lhs.bitBuffer[i] != rhs.bitBuffer[i] {
        return false
      }
    }

    // Verify that any extra words are all zeros.
    if i != lhsWords {
      while i != lhsWords {
        defer { i += 1 }
        if lhs.bitBuffer[i] != 0 {
          return false
        }
      }
    } else if i != rhsWords {
      while i != rhsWords {
        defer { i += 1 }
        if rhs.bitBuffer[i] != 0 {
          return false
        }
      }
    }
    return true
  }

  /// Computes the intersection of two bit vectors.
  public static func &= (lhs: inout BitVector, rhs: BitVector) {
    let lhsWords = numBitWords(lhs.bitCount)
    let rhsWords  = numBitWords(rhs.bitCount)
    let end = Swift.min(lhsWords, rhsWords)
    for i in 0..<end {
      lhs.bitBuffer[i] &= rhs.bitBuffer[i]
    }
    // Clear out now-unused bits if the lhs was the longer of the two.
    for i in end..<lhsWords {
      lhs.bitBuffer[i] = 0
    }
  }

  /// Computes the union of two bit vectors.
  public static func |= (lhs: inout BitVector, rhs: BitVector) {
    if lhs.bitCount < rhs.bitCount {
      lhs.grow(to: rhs.bitCount)
    }
    for i in 0..<numBitWords(rhs.bitCount) {
      lhs.bitBuffer[i] |= rhs.bitBuffer[i]
    }
  }

  /// Computes the disjoint union of two bit vectors.
  public static func ^= (lhs: inout BitVector, rhs: BitVector) {
    if lhs.bitCount < rhs.bitCount {
      lhs.grow(to: rhs.bitCount)
    }
    for i in 0..<numBitWords(rhs.bitCount) {
      lhs.bitBuffer[i] ^= rhs.bitBuffer[i]
    }
  }

}

private func numBitWords(_ blockCount: Int) -> Int {
  return (blockCount + chunkSizeInBits - 1) / chunkSizeInBits
}

private let chunkSizeInBits
    = MemoryLayout<BitVector.BitWord>.size * CChar.bitWidth
