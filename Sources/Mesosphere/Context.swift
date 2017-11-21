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

// MARK: Types

extension Context {
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

  private func insert(_ ty: TypeBase) -> TypeBase {
    self.types.insert(ty)
    return ty
  }
}

