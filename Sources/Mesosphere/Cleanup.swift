/// Cleanup.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography

/// Manages a stack of cleanup values on a per-function basis.
final class CleanupStack {
  typealias Handle = Int

  private(set) var stack: [Cleanup] = []

  init() {}

  /// Push a particular cleanup of a value.
  func pushCleanup(_ ty: Cleanup.Type, _ value: Value) -> CleanupStack.Handle {
    self.stack.append(ty.init(value: value))
    return self.stack.count - 1
  }

  /// Forward a given cleanup, disabling it in the process.
  func forwardCleanup(_ handle: CleanupStack.Handle) {
    precondition(handle >= 0, "invalid cleanup handle")
    let cleanup = self.stack[handle]
    assert(cleanup.state == .alive, "cannot forward dead cleanup")
    cleanup.deactivateForForward()
  }

  /// Emit cleanups up to a given depth into a continuation.
  func emitCleanups(
    _ GGF: GIRGenFunction, in continuation: Continuation,
    _ maxDepth: CleanupStack.Handle? = nil
  ) {
    guard !self.stack.isEmpty else {
      return
    }

    let depth = maxDepth ?? self.stack.count
    for cleanup in self.stack.prefix(depth).reversed() {
      guard cleanup.state == .alive else {
        continue
      }

      cleanup.emit(GGF, in: continuation)
    }
  }
}

/// A cleanup represents a known way to reclaim resources for a managed value.
class Cleanup {
  /// Enumerates the states that a cleanup can be in.
  public enum State {
    /// The cleanup is inactive.
    case dead
    /// The cleanup is active.
    case alive
  }

  let value: Value

  required init(value: Value) {
    self.value = value
  }

  private(set) var state: State = .alive

  fileprivate func deactivateForForward() {
    self.state = .dead
  }

  /// Emit this cleanup into the provided continuation.
  open func emit(_ GGF: GIRGenFunction, in cont: Continuation) {
    fatalError("Abstract cleanup cannot be emitted")
  }
}

final class DestroyValueCleanup: Cleanup {
  override func emit(_ GGF: GIRGenFunction, in cont: Continuation) {
    cont.appendCleanupOp(GGF.B.createDestroyValue(self.value))
  }
}

final class DeallocaCleanup: Cleanup {
  override func emit(_ GGF: GIRGenFunction, in cont: Continuation) {
    cont.appendCleanupOp(GGF.B.createDealloca(self.value))
  }
}
