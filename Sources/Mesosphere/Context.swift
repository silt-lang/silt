/// Context.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

/// A `Context` owns and manages core "global" data including the type and
/// constant uniquing tables.
///
/// Contexts faciliate separate or multi-threaded compilation but are not
/// themselves thread-safe.
public final class Context {
  public let name: String

  private var continuations: Set<Continuation> = []
  private var types: Set<TypeBase>

  var scopeEnd: ScopeEndContinuation? = nil

  init(withName name: String) {
    self.types = []
    self.name = name
  }
}

enum Intrinsic {
  /// Intrinsic memory reserve function
  case reserve

  /// Intrinsic atomic function
  case atomic

  /// Intrinsic cmpxchg function
  case cmpXchg

  /// Intrinsic undef function
  case undef

  /// branch(cond, T, F)
  case branch

  /// match(val, otherwise, (case1, cont1), (case2, cont2), ...)
  case match

  /// Partial evaluation debug info.
  case partialEvaluationInfo

  /// Dummy function which marks the end of a @p Scope.
  case endScope
}

// MARK: Types

extension Context {
  public func getOrCreateMemType() -> MemType {
    return getOrElse(MemType(in: self))
  }

  public func getOrCreateProductType(name: String, size: Int) -> ProductType {
    let type = ProductType(in: self, name: name, size: size)
    assert(self.types.insert(type).inserted)
    return type
  }

  public func getOrCreateFunctionType(_ types: [TypeBase]) -> FunctionType {
    return self.getOrElse(FunctionType(in: self, elements: types))
  }

  private func getOrElse<T: TypeBase>(_ type: T) -> T {
    guard let i = self.types.index(of: type) else {
      return self.insert(type) as! T
    }
    return self.types[i] as! T
  }

  var emptyFunctionType: FunctionType { return getOrCreateFunctionType([]) }

  func continuation(_ fn: FunctionType, intrinsic: Intrinsic? = nil,
                    dbg: Debug) -> Continuation {
    let l = Continuation(fn, intrinsic: intrinsic, debug: dbg)
    continuations.insert(l)

    for (idx, op) in fn.operands.enumerated() {
      let p = param(type: op, continuation: l, index: idx, debug: dbg)
      l.parameters.append(p)
    }

    return l
  }

  public func param(type: TypeBase, continuation: Continuation,
                    index: Int, debug: Debug) -> Continuation.Parameter {
    return Continuation.Parameter(type: type, continuation: continuation,
                                  index: index, debug: debug)
  }

  public func basicBlock(_ dbg: Debug) -> Continuation {
    let bb = Continuation(emptyFunctionType, debug: dbg)
    continuations.insert(bb)
    return bb
  }

  private func insert(_ ty: TypeBase) -> TypeBase {
    self.types.insert(ty)
    return ty
  }
}

