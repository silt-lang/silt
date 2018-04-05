/// StableHasher.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

// An implementation of SipHash24
///
/// Partially from the Swift Standard Library, partially from the Rust
/// Standard Library, partially from https://131002.net/siphash/.
public struct SipHasher {
  private enum Rounds {
    internal static func sipRound(
      v0: inout UInt64,
      v1: inout UInt64,
      v2: inout UInt64,
      v3: inout UInt64
    ) {
      v0 = v0 &+ v1
      v1 = rotateLeft(v1, by: 13)
      v1 ^= v0
      v0 = rotateLeft(v0, by: 32)
      v2 = v2 &+ v3
      v3 = rotateLeft(v3, by: 16)
      v3 ^= v2
      v0 = v0 &+ v3
      v3 = rotateLeft(v3, by: 21)
      v3 ^= v0
      v2 = v2 &+ v1
      v1 = rotateLeft(v1, by: 17)
      v1 ^= v2
      v2 = rotateLeft(v2, by: 32)
    }
  }

  private struct State {
    var v0: UInt64 = 0x736f6d6570736575
    var v1: UInt64 = 0x646f72616e646f6d
    var v2: UInt64 = 0x6c7967656e657261
    var v3: UInt64 = 0x7465646279746573
  }
  private var state: State = State()

  /// This value holds the byte count and the pending bytes that haven't been
  /// compressed yet, in the format that the finalization step needs. (The least
  /// significant 56 bits hold the trailing bytes, while the most significant 8
  /// bits hold the count of bytes appended so far, mod 256.)
  internal var tailAndByteCount: UInt64 = 0

  public init() {
    self.init(seed: (0, 0))
  }

  public init(seed: (UInt64, UInt64)) {
    self.state.v3 ^= seed.1
    self.state.v2 ^= seed.0
    self.state.v1 ^= seed.1
    self.state.v0 ^= seed.0
  }

  private var byteCount: UInt64 {
    return tailAndByteCount &>> 56
  }

  private var tail: UInt64 {
    return tailAndByteCount & ~(0xFF &<< 56)
  }

  private mutating func compress(_ value: UInt64) {
    self.state.v3 ^= value
    for _ in 0..<2 {
      Rounds.sipRound(v0: &self.state.v0, v1: &self.state.v1,
                       v2: &self.state.v2, v3: &self.state.v3)
    }
    self.state.v0 ^= value
  }
}

extension SipHasher: Hasher {
  public mutating func append(bits: UnsafeRawBufferPointer) {
    assert(bits.count <= 8)

    let length = UInt64(bits.count)

    let needed = 8 - self.tail
    let fill = min(length, needed)
    let m: UInt64
    if fill == 8 {
      m = bits.load(as: UInt64.self)
    } else {
      m = extendHostToLittle(bits, start: 0, length: fill)
    }
    tailAndByteCount = (tailAndByteCount | m) &+ (8 &<< 56)
    compress((m &<< 32) | tail)

    let ntail = length - needed
    let rest = extendHostToLittle(bits, start: Int(needed), length: ntail)
    tailAndByteCount = ((ntail &+ 8) &<< 56) | (rest &>> 32)
  }

  public mutating func append(bits: Int8) {
    var bitCpy = bits
    withUnsafeBytes(of: &bitCpy) { ptr in
      self.append(bits: ptr)
    }
  }

  public mutating func append(bits: UInt8) {
    var bitCpy = bits
    withUnsafeBytes(of: &bitCpy) { ptr in
      self.append(bits: ptr)
    }
  }

  public mutating func append(bits: Int16) {
    var bitCpy = bits
    withUnsafeBytes(of: &bitCpy) { ptr in
      self.append(bits: ptr)
    }
  }

  public mutating func append(bits: UInt16) {
    var bitCpy = bits
    withUnsafeBytes(of: &bitCpy) { ptr in
      self.append(bits: ptr)
    }
  }

  public mutating func append(bits: Int) {
    append(UInt(bitPattern: bits))
  }

  public mutating func append(bits: UInt) {
    append(UInt64(_truncatingBits: bits._lowWord))
  }

  public mutating func append(bits: Int32) {
    append(UInt32(bitPattern: bits))
  }

  public mutating func append(bits: UInt32) {
    let m = UInt64(_truncatingBits: bits._lowWord)
    if byteCount & 4 == 0 {
      assert(byteCount & 7 == 0 && tail == 0)
      tailAndByteCount = (tailAndByteCount | m) &+ (4 &<< 56)
    } else {
      assert(byteCount & 3 == 0)
      compress((m &<< 32) | tail)
      tailAndByteCount = (byteCount &+ 4) &<< 56
    }
  }

  public mutating func append(bits: Int64) {
    append(UInt64(bitPattern: bits))
  }

  public mutating func append(bits: UInt64) {
    if byteCount & 4 == 0 {
      assert(byteCount & 7 == 0 && tail == 0)
      compress(bits)
      tailAndByteCount = tailAndByteCount &+ (8 &<< 56)
    } else {
      assert(byteCount & 3 == 0)
      compress((bits &<< 32) | tail)
      tailAndByteCount = ((byteCount &+ 8) &<< 56) | (bits &>> 32)
    }
  }

  public mutating func finalize(
    tailBytes: UInt64,
    tailByteCount: Int
  ) -> UInt64 {
    assert(tailByteCount >= 0)
    assert(tailByteCount < 8 - (byteCount & 7))
    assert(tailBytes >> (tailByteCount << 3) == 0)
    let count = UInt64(_truncatingBits: tailByteCount._lowWord)
    let currentByteCount = byteCount & 7
    tailAndByteCount |= (tailBytes &<< (currentByteCount &<< 3))
    tailAndByteCount = tailAndByteCount &+ (count &<< 56)
    return finalize()
  }

  public mutating func finalize() -> UInt64 {
    compress(tailAndByteCount)

    self.state.v2 ^= 0xff

    for _ in 0..<4 {
      Rounds.sipRound(v0: &self.state.v0, v1: &self.state.v1,
                      v2: &self.state.v2, v3: &self.state.v3)
    }

    return self.state.v0 ^ self.state.v1 ^ self.state.v2 ^ self.state.v3
  }
}

// MARK: Utility Functions

private func extendHostToLittle(
  _ buf: UnsafeRawBufferPointer, start: Int, length: UInt64) -> UInt64 {
  assert(length < 8)
  var index = 0
  var out: UInt64 = 0
  if index + 3 < length {
    out = UInt64(buf.load(fromByteOffset: start + index, as: UInt32.self))
    index += 4
  }
  if index + 1 < length {
    let load = UInt64(buf.load(fromByteOffset: start + index, as: UInt16.self))
    out |= load << (index * 8)
    index += 2
  }
  if index < length {
    let load = buf.load(fromByteOffset: start + index, as: UInt64.self)
    out |= load << (index * 8)
    index += 1
  }
  assert(index == length)
  return out
}

private func rotateLeft(_ value: UInt64, by amount: UInt64) -> UInt64 {
  return (value &<< amount) | (value &>> (64 - amount))
}
