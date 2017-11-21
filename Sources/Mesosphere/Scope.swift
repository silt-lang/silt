/// Scope.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

/// The Scope of a continuation is the set of all continuations that are
/// transitively live from its point of view.
public final class Scope {
  public var definitions = Set<Definition>()
  public var continuations = [Continuation]()

  // Create and analyze the scope of a given continuation.
  init(entry: Continuation) {
    var queue = [Definition]()

    let enqueue = { (def: Definition) in
      if self.definitions.insert(def).inserted {
        queue.append(def)

        if let continuation = def as? Continuation {
          self.continuations.append(continuation)

          for param in continuation.parameters {
            assert(self.definitions.insert(param).inserted)
            queue.append(param)
          }
        }
      }
    }

    enqueue(entry)

    while !queue.isEmpty {
      let def = queue.removeFirst()
      guard def != entry else {
        continue
      }

      for use in def.uses {
        enqueue(use.definition)
      }
    }

    enqueue(entry.context.getOrCreateScopeEnd())
  }

  /// The entry function of this scope.
  public var entry: Continuation {
    return self.continuations.first!
  }

  /// The exit function of this scope - a special terminator continuation.
  public var exit: Continuation {
    return self.continuations.last!
  }

  /// Returns whether this scope contains a direct or indirect reference to
  /// the given definition.
  public func contains(_ def: Definition) -> Bool {
    return self.definitions.contains(def)
  }
}

public final class ScopeEndContinuation: Continuation {
  public static func inContext(_ context: Context) -> ScopeEndContinuation {
    return context.getOrCreateScopeEnd()
  }

  fileprivate init(in context: Context) {
    super.init(FunctionType(in: context))
  }
}

extension Context {
  func getOrCreateScopeEnd() -> ScopeEndContinuation {
    guard let se = self.scopeEnd else {
      let se = ScopeEndContinuation(in: self)
      self.scopeEnd = se
      return se
    }
    return se
  }
}
