/// ManagedValue.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography

/// A `ManagedValue` is a `(value, cleanup)` pair managing ownership of a GIR
/// value.  Ownership of the ManagedValue can be "forwarded" to disable its
/// cleanup when the value is known to be consumed by the caller.
struct ManagedValue {
  let value: Value
  private let cleanup: CleanupStack.Handle

  /// Create a managed value with no cleanup.
  static func unmanaged(_ value: Value) -> ManagedValue {
    return ManagedValue(unmanaged: value, cleanup: -1)
  }

  /// Initializes a managed value with a `(value, cleanup)` pair.
  init(value: Value, cleanup: CleanupStack.Handle) {
    precondition(cleanup >= 0,
     "cleanup handle cannot be invalid; use ManagedValue.unmanaged(_:) instead")
    self.value = value
    self.cleanup = cleanup
  }

  private init(unmanaged: Value, cleanup: CleanupStack.Handle) {
    self.value = unmanaged
    self.cleanup = cleanup
  }

  /// Emit a copy of this value with independent ownership.
  func copy(_ GGF: GIRGenFunction) -> ManagedValue {
    switch self.value.type.category {
    case .object:
      let value = GGF.B.createCopyValue(self.value)
      return ManagedValue(value: value, cleanup: GGF.cleanupValue(value))
    case .address:
      let alloc = GGF.B.createAlloca(self.value.type)
      let addr = GGF.B.createCopyAddress(self.value, to: alloc)
      return ManagedValue(value: value, cleanup: GGF.cleanupAddress(addr))
    }
  }

  /// Forward this value, deactivating the cleanup and returning the
  /// underlying value.
  func forward(_ GGF: GIRGenFunction) -> Value {
    if self.cleanup >= 0 {
      GGF.cleanupStack.forwardCleanup(self.cleanup)
    }
    return self.value
  }
}
