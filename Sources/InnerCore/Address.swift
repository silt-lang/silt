/// Address.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import LLVM

/// The address of an object in memory.
struct Address {
  let address: IRValue
  let alignment: Alignment
  let pointeeType: IRType

  init(_ addr: IRValue, _ align: Alignment, _ pointeeType: IRType) {
    self.address = addr
    self.alignment = align
    self.pointeeType = pointeeType
  }
}

/// An address in memory together with the (possibly null) heap
/// allocation which owns it.
struct OwnedAddress {
  let address: Address
  let owner: IRValue

  init(_ addr: Address, _ owner: IRValue) {
    self.address = addr
    self.owner = owner
  }

  var alignment: Alignment {
    return self.address.alignment
  }
}

/// An address on the stack together with an optional stack pointer reset
/// location.
struct StackAddress {
  /// The address of an object of type T.
  let address: Address

  /// In a normal function, the result of llvm.stacksave or null.
  /// In a coroutine, the result of llvm.coro.alloca.alloc.
  let extraInfo: IRValue?

  init(_ address: Address, _ extraInfo: IRValue? = nil) {
    self.address = address
    self.extraInfo = extraInfo
  }

  func withAddress(_ addr: Address) -> StackAddress {
    return StackAddress(addr, self.extraInfo)
  }

  var alignment: Alignment {
    return self.address.alignment
  }
}
