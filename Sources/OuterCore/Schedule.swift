/// Schedule.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography

/// A schedule adds SSA-like operations before a CPS-style call. 
final class Schedule {
  /// Whether this operation is scheduled early (before the 'terminator'), or
  /// late (after the 'terminator').
  enum Tag {
    case early
    case late
  }

  /// A 'block' abstraction that 
  final class Block: Equatable, Hashable {
    var parent: Continuation
    var primops: [PrimOp]
    var index: Int

    init(_ parent: Continuation, _ primops: [PrimOp], _ idx: Int) {
      self.parent = parent
      self.primops = primops
      self.index = idx
    }

    public static func == (lhs: Block, rhs: Block) -> Bool {
      return lhs === rhs
    }

    public var hashValue: Int {
      return "\(ObjectIdentifier(self).hashValue)".hashValue
    }
  }

  let scope: Scope
  let tag: Tag
  var blocks: [Block] = []
  var indices: [Continuation: Int] = [:]
  init(_ scope: Scope, _ tag: Tag) {
    self.scope = scope
    self.tag = tag

    // until we have sth better simply use the RPO of the CFG
    var i = 0
    for n in scope.entry.reversePostOrder {
      defer { i += 1 }
      self.blocks.append(Block(n, [], i))
      self.indices[n] = i
    }
    _ = Scheduler(self)
  }

  func block(_ c: Continuation) -> Block {
    return self.blocks[self.indices[c]!]
  }

  func dump() {
    for block in self.blocks {
      block.parent.dump()
      for primop in block.primops {
        primop.dump()
      }
    }
  }
}

private final class Scheduler {
  let scope: Scope
  let schedule: Schedule

  private var def2early = [Value: Continuation]()
  private var def2late = [Value: Continuation]()

  init(_ schedule: Schedule) {
    self.scope = schedule.scope
    self.schedule = schedule
    switch schedule.tag {
    case .early:
      for cont in self.scope.continuations {
        guard let terminal = cont.terminalOp else { continue }
        self.schedulePrimopsEarly(in: cont, terminal)
      }
    case .late:
      fatalError()
//      for (primop, _) in def2uses where primop is PrimOp {
//        _ = self.schedule_late(primop)
//      }
    }
  }

  func schedulePrimopsEarly(in cont: Continuation, _ term: TerminalOp) {
    var queue = [PrimOp]()
    var visited = Set<Value>()
    var schedule = [PrimOp]()

    queue.append(term)

    while let op = queue.popLast() {
      guard visited.insert(op).inserted else { continue }
      schedule.append(op)

      for operand in op.operands {
        guard let prim = operand.value as? PrimOp else { continue }
        queue.append(prim)
      }
    }
    let activeBlock = self.schedule.block(cont)
    for s in schedule.reversed().dropLast() {
      activeBlock.primops.append(s)
    }
    for destroy in cont.destroys {
      activeBlock.primops.append(destroy)
    }
    activeBlock.primops.append(term)
  }
}
