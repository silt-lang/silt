/// Validation.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

protocol Monoid {
  func mappend(_ other: Self) -> Self
}

// The Collect Monad is the dual of the Validation Monad: where Validation
// gathers and appends errors, Collect gathers and values.
indirect enum Collect<Err, M: Monoid> {
  case fail(Err)
  case collect(M)
}

extension Collect: Monoid {
  func mappend(_ other: Collect) -> Collect {
    switch (self, other) {
    case let (.fail(e), _): return .fail(e)
    case let (_, .fail(e)): return .fail(e)
    case let (.collect(m1), .collect(m2)): return .collect(m1.mappend(m2))
    }
  }
}

extension Set: Monoid {
  func mappend(_ other: Set<Element>) -> Set<Element> {
    return self.union(other)
  }
}

enum Either<Fail, Succ> {
  case left(Fail)
  case right(Succ)

  func map<T>(_ f: (Succ) -> T) -> Either<Fail, T> {
    switch self {
    case let .left(e): return .left(e)
    case let .right(s): return .right(f(s))
    }
  }
}

enum Validation<Fail: Monoid, Succ> {
  case failure(Fail)
  case success(Succ)

  func merge(_ other: Validation) -> Validation {
    switch (self, other) {
    case let (.failure(f1), .failure(f2)): return .failure(f1.mappend(f2))
    case (.failure(_), _): return self
    case (_, .failure(_)): return other
    case (.success(_), _): return other
    }
  }

  func merge2<T>(_ other: Validation<Fail, T>) -> Validation<Fail, (Succ, T)> {
    switch (self, other) {
    case let (.failure(f1), .failure(f2)): return .failure(f1.mappend(f2))
    case let (.failure(e), _): return .failure(e)
    case let (_, .failure(f)): return .failure(f)
    case let (.success(t1), .success(t2)): return .success((t1, t2))
    }
  }

  func map<T>(_ f: (Succ) -> T) -> Validation<Fail, T> {
    switch self {
    case let .failure(e): return .failure(e)
    case let .success(s): return .success(f(s))
    }
  }
}

extension Sequence {
  func mapM<T>(_ transform: (Element) -> T?) -> [T]? {
    var result = [T]()
    for el in self {
      guard let transEl = transform(el) else {
        return nil
      }
      result.append(transEl)
    }
    return result
  }

  func mapM<E, T>(
    _ transform: (Element) -> Validation<E, T>) -> Validation<E, [T]> {
    var result = [T]()
    for el in self {
      switch transform(el) {
      case let .failure(f):
        return .failure(f)
      case let .success(s):
        result.append(s)
      }
    }
    return .success(result)
  }
}
