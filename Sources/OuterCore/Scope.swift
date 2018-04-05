/// Scope.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Seismography

final class Scope {
  private var defs = Set<Value>()
  let entry: Continuation
  var continuations: [Continuation] = []

  var definitions: Set<Value> {
    return self.defs
  }

  init(_ entry: Continuation, _ blacklist: Set<Continuation>) {
    self.entry = entry
    var queue = [Value]()

    Scope.enqueue(&queue, &self.defs, &self.continuations, entry, blacklist)

    while !queue.isEmpty {
      let def = queue.removeFirst()
      guard def != entry else {
        continue
      }

      guard !(def is Continuation) else {
        Scope.enqueue(&queue, &self.defs, &self.continuations, def, blacklist)
        continue
      }

      for use in def.users {
        Scope.enqueue(&queue, &self.defs, &self.continuations,
                      use.user, blacklist)
      }
    }
  }

  func contains(_ val: Value) -> Bool {
    return self.defs.contains(val)
  }

  func dump() {
    var stream = FileHandle.standardOutput
    GIRWriter(stream: &stream).writeSchedule(Schedule(self, .early))
  }

  private static func enqueue(
    _ queue: inout [Value], _ defs: inout Set<Value>,
    _ conts: inout [Continuation], _ val: Value,
    _ blacklist: Set<Continuation>) {
    guard defs.insert(val).inserted else {
      return
    }
    queue.append(val)

    if let continuation = val as? Continuation {
      guard !blacklist.contains(continuation) else {
        return
      }

      conts.append(continuation)

      for param in continuation.parameters {
        assert(defs.insert(param).inserted)
        queue.append(param)
      }
    } else if let terminal = val as? TerminalOp {
      queue.append(terminal.parent)
      for succ in terminal.successors {
        guard let succ = succ.successor else { continue }

        queue.append(succ)
      }
    }
  }
}

extension Scope {
  /// A sequence that iterates over the reverse post-order traversal of this
  /// graph.
  var reversePostOrder: ReversePostOrderSequence<Continuation> {
    return ReversePostOrderSequence(root: self.entry,
                                    mayVisit: Set(self.continuations))
  }
}
