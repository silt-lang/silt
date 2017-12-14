/// Continuation.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

/// A continuation represents a function that, once called, never returns.  Its
/// body consists solely of primitive operations and calls to other
/// continuations.
public class Continuation: Definition {
  public struct Todo {
    let handle: Int
    let index: Int
    let type: TypeBase
    let debug: Debug
  }
  public class Parameter: Definition {
    weak var parent: Continuation?
    let index: Int
    var debug: Debug

    init(type: TypeBase, continuation: Continuation, index: Int,
         debug: Debug) {
      self.parent = continuation
      self.index = index
      self.debug = Debug()
      super.init(type: type)
    }
  }

  /// The argument parameters to this continuation.
  public var parameters: [Parameter] = []
  public var todos = [Todo]()
  public var parent: Continuation?
  public var isSealed = false
  public var isVisited = false
  let debug: Debug
  let intrinsic: Intrinsic?
  var jumpDebug: Debug?

  init(_ fn: FunctionType, intrinsic: Intrinsic? = nil,
       debug: Debug = Debug()) {
    super.init(type: fn)
    self.debug = debug
    self.intrinsic = intrinsic
    self.parameters.reserveCapacity(fn.operands.count)
  }

  public var callee: Definition {
    if self.operands.isEmpty {
      fatalError()
    }
    return self.operands[0]
  }

  public var arguments: [Definition] {
    if self.operands.count == 0 {
      return []
    }
    return self.operands.dropFirst().map{$0}
  }

  func findDefinition(_ handle: Int) -> Definition? { return nil }

  func getValue(handle: Int, type: TypeBase, dbg: Debug) -> Definition? {
    let checkResult: (Definition) -> Definition = { result in
      assert(result.type === type)
      return result
    }
    let bottom: () -> Definition = {
      print("warning: \(dbg.name) might be undefined")
      return setValue(handle, context.bottom(type))
    }
    if let result = findDefinition(handle) {
      return checkResult(result)
    }

    if let parent = parent, parent !== self { // is a function head?
      return checkResult(parent.getValue(handle: handle, type: type, dbg: dbg))
    } else {
      if !isSealed {
        let param: Definition = appendParam(type, dbg)
        todos.append(Todo(handle: handle, index: param.index,
                          type: type, debug: dbg))
        return checkResult(setValue(handle, param))
      }

      let preds = computePredecessors(direct: true, indirect: true)
      switch preds.count {
      case 0:
        return bottom()
      case 1:
        return checkResult(setValue(handle, preds[0].getValue(handle, type, dbg)))
      default:
        if isVisited {
          // create param to break cycle
          return checkResult(setValue(handle, appendParam(type, dbg)))
        }

        isVisited = true
        var _same: Definition?
        var isFromPred = false
        for pred in preds {
          let def = pred.getValue(handle: handle, type: type, dbg: dbg)
          if let s = _same, _same !== def {
            isFromPred = true // defs from preds are different
            break
          }
          _same = def
        }
        guard let same = _same else { fatalError() }
        isVisited = false

        // fix any params which may have been introduced to break the cycle above
        var def: Definition?
        if let found = findDefinition(handle) {
          def = fix(handle, (found as! Param).index, type, dbg)
        }

        if !isFromPred {
          return checkResult(same)
        }

        if let d = def {
          return checkResult(setValue(handle, def))
        }

        let param = appendParam(type, dbg)
        setValue(handle, param)
        fix(handle, param.index, type, dbg)
        return checkResult(param)
      }
    }
  }

  var mem: Definition? {
    get {
      return getValue(handle: 0, type: context.getOrCreateMemType(),
                      dbg: Debug(name: "mem"))
    }
    set {
      setValue(0, newValue)
    }
  }

  func jump(callee: Definition, args: [Definition], dbg: Debug) {
      jumpDebug = dbg
      if let continuation = callee as? Continuation {
        switch continuation.intrinsic {
        case .branch?:
          assert(args.count == 3)
          let cond = args[0], t = args[1], f = args[2]
          if let lit = cond as? PrimLit {
            return jump(lit.value.booleanValue ? t : f, args: [], dbg: dbg)
          }
          if t === f {
            return jump(callee: t, args: [], dbg: dbg)
          }
          if isNot(cond) {
            return branch(cond.operands[1], f, t, dbg)
          }
        case .match?:
          if args.count == 2 { return jump(callee: args[1], args: [], dbg: dbg) }
        if let lit = args[0] as? PrimLit {
          for arg in args.dropFirst(2) {
            if (context.extract(arg, 0) as? PrimLit) === lit {
              return jump(context.extract(arg, 1), args: [], dbg: dbg)
            }
          }
          return jump(args[1], args: [], dbg: dbg)
        }
        default:
          break
        }
      }

    unsetOps()
    setOperand(at: 0, to: callee)

    for (idx, arg) in args {
      setOperand(at: idx, to: arg)
    }

    verify()
  }

  func unsetOperand(at index: Int)= {
  unregister_use(i);
  ops_[i] = nullptr;
  }

  void Def::unset_ops() {
  for (size_t i = 0, e = num_ops(); i != e; ++i)
  unset_op(i);
  }

  func jump(to jumpTarget: JumpTarget, dbg: Debug) {
    if jumpTarget.continuation == nil {
      jumpTarget.continuation = self
      jumpTarget.isFirst = true
    } else {
      jump(callee: jumpTarget.untangle()!, args: [], dbg: dbg)
    }
  }

  func seal() {
    precondition(!isSealed, "attempt to seal already sealed continuation")
    isSealed = true

    for todo in todos {
      fix(todo.handle, todo.index, todo.type, todo.debug)
    }
    todos = []
  }

  func computeSuccessors(direct: Bool, indirect: Bool) -> [Continuation] {
    var succs = [Continuation]()
    var queue = [Definition]()
    var done: Set<Definition> = []

    let enqueue = { (def: Definition) in
      if !done.contains(def) {
        queue.append(def)
        done.insert(def)
      }
    }

    done.insert(self)

    if direct && !self.operands.isEmpty {
      enqueue(self.callee)
    }

    if indirect {
      for arg in self.arguments {
        enqueue(arg)
      }
    }

    while !queue.isEmpty{
      let def = queue.removeFirst()
      if let continuation = def as? Continuation {
        succs.append(continuation)
        continue
      }

      for op in def.operands {
        if op.order >= 1 {
          enqueue(op)
        }
      }
    }

    return succs
  }

  func computePredecessors(direct: Bool, indirect: Bool) -> [Continuation] {
    var preds = [Continuation]()
    var queue = [Use]()
    var done: Set<Definition> = []

    let enqueue = { (def: Definition) in
      for use in def.uses {
        if !done.contains(def) {
          queue.append(use)
          done.insert(use.definition)
        }
      }
    }

    enqueue(self)

    while !queue.isEmpty{
      let use = queue.removeFirst()
      if let continuation = use.definition as? Continuation {
        if (use.index == 0 && direct) || (use.index != 0 && indirect) {
          preds.append(continuation)
        }
        continue
      }

      enqueue(use.definition)
    }

    return preds
  }
}

public class TerminatorContinuation: Continuation {}

