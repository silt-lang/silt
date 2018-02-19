//
//  Scope.swift
//  siltPackageDescription
//
//  Created by Robert Widmann on 2/20/18.
//

import Foundation

final class Scope {
  private var defs = Set<Value>()
  let cfg: CFG
  let entry: Continuation
  var continuations: [Continuation] = []

  init(_ entry: Continuation) {
    self.entry = entry
    var queue = [Value]()

    Scope.enqueue(&queue, &self.defs, &self.continuations, entry)

    while !queue.isEmpty {
      let def = queue.removeFirst()
      guard def != entry else {
        continue
      }
      for use in def.users {
        Scope.enqueue(&queue, &self.defs, &self.continuations, use.user)
      }
    }
    self.cfg = CFG(entry, continuations.count)
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
    _ conts: inout [Continuation], _ val : Value) {
    guard defs.insert(val).inserted else {
      return
    }

    guard let continuation = val as? Continuation else {
      return
    }
    conts.append(continuation)

    for param in continuation.parameters {
      assert(defs.insert(param).inserted)
      queue.append(param)
    }
  }
}
