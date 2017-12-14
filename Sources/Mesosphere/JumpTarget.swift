//
//  JumpTarget.swift
//  Mesosphere
//
//  Created by Harlan Haskins on 12/13/17.
//

import Foundation

final class JumpTarget {
  let debug: Debug
  var continuation: Continuation?
  var isFirst = false

  init(debug: Debug) {
    self.debug = debug
  }

  var name: String { return debug.name }

  var context: Context {
    guard let continuation = continuation else {
      fatalError("cannot get context of jump target with no continuation")
    }
    return continuation.context
  }

  func seal() {
    guard let continuation = continuation else {
      fatalError("cannot seal jump target with no continuation")
    }
    continuation.seal()
  }

  func untangle() -> Continuation? {
    if !isFirst {
      return continuation
    }
    guard let continuation = continuation else {
      fatalError("cannot untangle jump target with no continuation")
    }
    let bb = context.basicBlock(debug)
    continuation.jump(callee: bb, args: [], dbg: debug);
    isFirst = false
    self.continuation = bb
    return continuation
  }

  func branch(to context: Context, dbg: Debug) -> Continuation {
    let name: String
    if continuation == nil {
      name = dbg.name
    } else {
      name = "\(dbg.name)_crit"
    }
    let bb = context.basicBlock(dbg + name)
    bb.jump(to: self, dbg: dbg)
    bb.seal()
    return bb
  }

  func enter() -> Continuation? {
    if let continuation = continuation, !isFirst {
      continuation.seal()
    }
    return continuation;
  }

  func enterUnsealed(context: Context) -> Continuation? {
    if continuation != nil {
      return untangle()
    } else {
      continuation = context.basicBlock(Debug())
    }
  }

  #if DEBUG
  deinit {
    guard continuation == nil || first || continuation.isSealed else {
      fatalError("JumpTarget not sealed")
    }
  }
  #endif

}
