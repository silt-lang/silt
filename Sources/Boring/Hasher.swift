/// Hasher.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public protocol Hasher {
  associatedtype HashValueType

  /// Initialize a new hasher from the default seed value.
  /// The default seed is set during process startup, usually from a
  /// high-quality random source.
  init()
  /// Initialize a new hasher from the specified seed value.
  init(seed: (UInt64, UInt64))

  /// Append the bit pattern `bits` to this hasher.
  /// This adds exactly `Int.bitWidth` bits to the hasher state,
  /// in native byte order.
  mutating func append(bits: Int)

  /// Append the bit pattern `bits` to this hasher.
  /// This adds exactly `UInt.bitWidth` bits to the hasher state,
  /// in native byte order.
  mutating func append(bits: UInt)

  /// Append the bit pattern `bits` to this hasher.
  /// This adds exactly 8 bytes to the hasher state, in native byte order.
  mutating func append(bits: Int64)

  /// Append the bit pattern `bits` to this hasher.
  /// This adds exactly 8 bytes to the hasher state, in native byte order.
  mutating func append(bits: UInt64)

  /// Append the bit pattern `bits` to this hasher.
  /// This adds exactly 4 bytes to the hasher state, in native byte order.
  mutating func append(bits: Int32)

  /// Append the bit pattern `bits` to this hasher.
  /// This adds exactly 4 bytes to the hasher state, in native byte order.
  mutating func append(bits: UInt32)

  /// Append the bit pattern `bits` to this hasher.
  /// This adds exactly 2 bytes to the hasher state, in native byte order.
  mutating func append(bits: Int16)

  /// Append the bit pattern `bits` to this hasher.
  /// This adds exactly 2 bytes to the hasher state, in native byte order.
  mutating func append(bits: UInt16)

  /// Append the single byte `bits` to this hasher.
  mutating func append(bits: Int8)
  /// Append the single byte `bits` to this hasher.
  mutating func append(bits: UInt8)

  /// Append the raw bytes in `buffer` to this hasher.
  mutating func append(bits buffer: UnsafeRawBufferPointer)

  /// Finalize the hasher state and return the hash value.
  /// Finalizing invalidates the hasher; it cannot be appended to or
  /// finalized again.
  mutating func finalize() -> HashValueType
}

extension Hasher {
  /// Append `value` to this hasher.
  mutating func append<H: HashableByHasher>(_ value: H) {
    value.hash(into: &self)
  }
}

public protocol HashableByHasher: Hashable {
  /// Hash the essential components of this value into the hash function
  /// represented by `hasher`, by appending them to it.
  ///
  /// Essential components are precisely those that are compared in the type's
  /// implementation of `Equatable`.
  func hash<H: Hasher>(into hasher: inout H)
}

extension Int8: HashableByHasher {
  public func hash<H: Hasher>(into hasher: inout H) {
    hasher.append(bits: self)
  }
}
extension Int16: HashableByHasher {
  public func hash<H: Hasher>(into hasher: inout H) {
    hasher.append(bits: self)
  }
}
extension Int32: HashableByHasher {
  public func hash<H: Hasher>(into hasher: inout H) {
    hasher.append(bits: self)
  }
}
extension Int64: HashableByHasher {
  public func hash<H: Hasher>(into hasher: inout H) {
    hasher.append(bits: self)
  }
}
extension Int: HashableByHasher {
  public func hash<H: Hasher>(into hasher: inout H) {
    hasher.append(bits: self)
  }
}

extension UInt8: HashableByHasher {
  public func hash<H: Hasher>(into hasher: inout H) {
    hasher.append(bits: self)
  }
}
extension UInt16: HashableByHasher {
  public func hash<H: Hasher>(into hasher: inout H) {
    hasher.append(bits: self)
  }
}
extension UInt32: HashableByHasher {
  public func hash<H: Hasher>(into hasher: inout H) {
    hasher.append(bits: self)
  }
}
extension UInt64: HashableByHasher {
  public func hash<H: Hasher>(into hasher: inout H) {
    hasher.append(bits: self)
  }
}
extension UInt: HashableByHasher {
  public func hash<H: Hasher>(into hasher: inout H) {
    hasher.append(bits: self)
  }
}

