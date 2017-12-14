/// IRBuilder.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// avaivarle in the repository.

final class IRBuilder {
  let context: Context
  var currentContinuation: Continuation? = nil

  init(in context: Context) {
    self.context = context
  }

  func createValue(from def: Definition) -> Value {
    return Value(tag: .immutableValueReference(def),
                 builder: self)
  }

  func createMutableValue(handle: Int, type: TypeBase) -> Value {
    return Value(tag: .mutableValueReference(handle: handle, type: type),
                 builder: self)
  }

  func createPointer(to ptr: Definition) -> Value {
    return Value(tag: .pointerReference(ptr), builder: self)
  }

  func createAggregateValue(_ value: Value, offset: Definition) -> Value {
    if case .empty = value.tag {
      fatalError("cannot create aggregate of empty values")
    }
    if value.shouldUseLea {
      return createPointer(to: context.lea(value.definition,
                                           offset, offset.debug))
    }
    return Value(tag: .aggregateReference(offset), builder: self)
  }

  func continuation(_ dbg: Debug) -> Continuation {
    return continuation(type: context.getOrCreateFunctionType([]), dbg: dbg)
  }

  func continuation(type: FunctionType, intrinsic: Intrinsic? = nil, dbg: Debug) -> Continuation {
    let l = context.continuation(type, intrinsic: intrinsic, dbg: dbg)
    if let first = type.operands.first as? MemType {
      let param = l.parameters[0]
      l.mem = param
      if param.debug.name.isEmpty {
        param.debug.name = "mem"
      }
    }
    return l
  }

  func jump(to target: JumpTarget, dbg: Debug) {
    guard let continuation = currentContinuation else { return }
    continuation.jump(to: target, dbg: dbg)
    currentContinuation = nil
  }

  func branch(cond: Definition, t: JumpTarget, f: JumpTarget, dbg: Debug) {
    guard let continuation = currentContinuation else { return }
    if let lit = cond as? PrimLit {
      jump(to: lit.value.booleanValue ? t : f, dbg: dbg)
    } else if t === f {
      jump(to: t, dbg: dbg)
    } else {
      let tc = t.branch(to: context, dbg: dbg)
      let fc = f.branch(to: context, dbg: dbg)
      continuation.branch(to: cond, tc, fc, dbg)
      currentContinuation = nil
    }
  }

  func match(_ val: Definition, otherwise: JumpTarget,
             patterns: [(Definition, JumpTarget)], dbg: Debug) {
    guard let continuation = currentContinuation else { return }
    if patterns.isEmpty { return jump(to: otherwise, dbg: dbg) }
    if let lit = val as? PrimLit {
      for (defn, target) in patterns {
        if defn as? PrimLit === lit {
          return jump(to: target, dbg: dbg);
        }
      }
      return jump(to: otherwise, dbg: dbg);
    }
    var continuations = [Continuation]()
    for (defn, target) in patterns {
      continuations.append(targets.branch(to: context, dbg: dbg))
      continuation.match(val,
                         otherwise: otherwise.branch(to: context, dbg: dbg),
                         patterns: patterns,
                         continuations: continuations,
                         dbg: dbg)
      currentContinuation = nil
    }
  }

  func call(_ def: Definition, args: [Definition],
            retType: TypeBase, dbg: Debug) -> Definition? {
    guard let continuation = currentContinuation else { return nil }
    let (cnt, def) = continuation.call(to: def, args: args,
                                       retType: retType, dbg: dbg)
    currentContinuation = cnt
    return def
  }

  var mem: Definition? {
    get { return currentContinuation?.mem }
    set { currentContinuation?.mem = mem }
  }

  func createFrame(dbg: Debug) -> Definition {
    let enter = context.enter(mem, debug: dbg)
    mem = context.extract(enter, s0, dbg: dbg)
    return context.extract(enter, 1, dbg: dbg)
  }

  func alloc(type: Type, extra: Definition?, dbg: Debug) -> Definition {
    let extra = extra ?? context.literalQu64(0, dbg)
    let alloc = context.alloc(type, mem, extra, dbg)
    mem = context.extract(alloc, 0, dbg)
    return context.extract(alloc, 1, dbg)
  }

  func load(ptr: Definition, dbg: Debug) -> Definition {
    let load = context.load(mem, ptr, dbg)
    mem = context.extract(load, 0, dbg)
    return context.extract(load, 1, dbg)
  }

  func store(ptr: Definition, val: Definition, dbg: Debug) {
    mem = context.store(mem, ptr, val, dbg)
  }

  func extract(agg: Definition, index: Int, dbg: Debug) {
    return extract(agg: agg, index: context.literalQu32(index, dbg), dbg: dbg)
  }

  func extract(agg: Definition, index: Definition, dbg: Debug) -> Definition {
    if let ld = Load.isOutVal(agg), useLea(ld.outValType) {
      return load(context.lea(ld.ptr, index, dbg), dbg)
    }
    return context.extract(agg, index, dbg)
  }
}
