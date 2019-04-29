/// IRValueBehaviors.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import LLVM

extension Triple {
  func pointerSpareBits() -> BitVector {
    var bitVector = BitVector()
    switch self.architecture {
    case .x86_64:
      // Only the bottom 56 bits are used, and heap objects are
      // eight-byte-aligned.
      bitVector.append(bits: 64, from: 0xFF00000000000007)
    case .x86:
      // Heap objects are pointer-aligned, so the low two bits are unused.
      bitVector.append(bits: 32, from: 0x00000003)
    case .arm, .thumb:
      // Heap objects are pointer-aligned, so the low two bits are unused.
      bitVector.append(bits: 32, from: 0x00000003)
    case .aarch64:
      // TBI guarantees the top byte of pointers is unused, but ARMv8.5-A
      // claims the bottom four bits of that for memory tagging.
      // Heap objects are eight-byte aligned.
      bitVector.append(bits: 64, from: 0xF000000000000007)
    case .ppc64, .ppc64le:
      // Only the bottom 56 bits are used, and heap objects are
      // eight-byte-aligned.
      bitVector.append(bits: 64, from: 0xFF00000000000007)
    case .systemz:
      // Only the bottom 56 bits are used, and heap objects are
      // eight-byte-aligned.
      bitVector.append(bits: 64, from: 0xFF00000000000007)
    default:
      fatalError("Unknown architecture!")
    }
    return bitVector
  }
}
