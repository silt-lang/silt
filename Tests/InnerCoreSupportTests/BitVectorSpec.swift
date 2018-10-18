/// BitVectorSpec.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import InnerCore
import XCTest

class BitVectorSpec: XCTestCase {
  func testEmptyBitCount() {
    let vec = BitVector()
    XCTAssertEqual(0, vec.nonzeroBitCount())
    XCTAssertEqual(0, vec.count)
    XCTAssertFalse(vec.any())
    XCTAssertTrue(vec.none())
    XCTAssertTrue(vec.isEmpty)
  }

  func testVectorAppend() {
    var vec = BitVector()

    vec.appendSetBits(5)
    XCTAssertEqual(5, vec.nonzeroBitCount())
    XCTAssertEqual(5, vec.count)
    XCTAssertTrue(vec.any())
    XCTAssertFalse(vec.none())
    XCTAssertFalse(vec.isEmpty)

    vec.appendClearBits(6)
    XCTAssertEqual(5, vec.nonzeroBitCount())
    XCTAssertEqual(64, vec.capacity)
    XCTAssertTrue(vec.any())
    XCTAssertFalse(vec.none())
    XCTAssertFalse(vec.isEmpty)
  }

  func testVectorFlip() {
    var vec = BitVector()
    vec.appendSetBits(5)
    vec.appendClearBits(6)

    var inv = vec
    inv.flipAll()
    XCTAssertEqual(6, inv.nonzeroBitCount())
    XCTAssertEqual(11, inv.count)
    XCTAssertTrue(inv.any())
    XCTAssertFalse(inv.none())
    XCTAssertFalse(inv.isEmpty)

    XCTAssertFalse(inv == vec)
    XCTAssertTrue(inv != vec)
    vec.flipAll()
    XCTAssertTrue(inv == vec)
    XCTAssertFalse(inv != vec)
  }

  func testSetBitIterator() {
    var vec = BitVector()
    vec.appendSetBits(23)
    vec.appendClearBits(25)
    vec.appendSetBits(26)
    vec.appendClearBits(29)
    vec.appendSetBits(33)
    vec.appendClearBits(57)
    var itCounter = 0
    for i in AnySequence({vec.makeSetBitIterator()}) {
      itCounter += 1
      XCTAssertTrue(vec[i])
      XCTAssertTrue(vec.testBit(at: i))
    }
    XCTAssertEqual(itCounter, vec.nonzeroBitCount())
    XCTAssertEqual(itCounter, 23+26+33)
    vec.flipAll()
    XCTAssertEqual(vec.count - itCounter, vec.nonzeroBitCount())
  }

  func testRemoval() {
    var vec = BitVector()
    vec.appendSetBits(23)
    vec.appendClearBits(25)
    vec.removeAll()
    XCTAssertEqual(0, vec.nonzeroBitCount())
    XCTAssertEqual(0, vec.count)
    XCTAssertFalse(vec.any())
    XCTAssertTrue(vec.none())
    XCTAssertTrue(vec.isEmpty)
  }

  func testReserveIdempotent() {
    var vec = BitVector()
    vec.reserveCapacity(1_000)
    XCTAssertEqual(0, vec.nonzeroBitCount())
    XCTAssertEqual(0, vec.count)
    XCTAssertFalse(vec.any())
    XCTAssertTrue(vec.none())
    XCTAssertTrue(vec.isEmpty)
    vec.flipAll()
    XCTAssertEqual(0, vec.nonzeroBitCount())
    XCTAssertEqual(0, vec.count)
    XCTAssertFalse(vec.any())
    XCTAssertTrue(vec.none())
    XCTAssertTrue(vec.isEmpty)
  }

  #if !(os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
  static var allTests = testCase([
    ("testEmptyBitCount", testEmptyBitCount),
    ("testVectorAppend", testVectorAppend),
    ("testVectorFlip", testVectorFlip),
    ("testSetBitIterator", testSetBitIterator),
    ("testRemoval", testRemoval),
    ("testReserveIdempotent", testReserveIdempotent),
  ])
  #endif
}
