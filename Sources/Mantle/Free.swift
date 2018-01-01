/// Free.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

/// `FreeVariables` contains the set of free rigid and flexible variables
/// contained in an expression.
struct FreeVariables {
  /// Those variables that do not appear as the argument of a metavariable.
  ///
  /// So-named by Miller because these variables are "permanent" as opposed to
  /// "possible" - substitution will not remove these variables.
  ///
  /// Metavariables that contain rigid versions of themselves fail the occurs
  /// check.
  ///
  /// Both `Y` and `Z` in `$0[X] -> Y[Z]`
  let rigid: Set<Var>
  /// Those variables that appear as the arguments of a metavariable.
  ///
  /// So-named by Miller because these variables are "possible" as opposed to
  /// "permanent" - substitutions performed against the metavariable may remove
  /// these by substituting for further metavariables.
  ///
  /// The `X` in `$0[X] -> Y[Z]`
  let flexible: Set<Var>

  /// Initializes a new empty set of free variables.
  init() {
    self.rigid = []
    self.flexible = []
  }

  /// Initializes a set of free variables with the given sets of rigid and
  /// flexible variables.
  init(_ rigid: Set<Var>, _ flexible: Set<Var>) {
    self.rigid = rigid
    self.flexible = flexible
  }

  /// Returns the union of the rigid and flexible variables, preferring rigid
  /// variables if overlap occurs.
  var all: Set<Var> {
    return self.rigid.union(self.flexible)
  }

  fileprivate func append(_ other: FreeVariables) -> FreeVariables {
    return FreeVariables(other.rigid.union(self.rigid),
                         self.flexible.union(other.flexible))
  }
}

extension TypeChecker {
  /// Compute the rigid and flexible free variables present in a given
  /// expression.
  ///
  /// - warning: This operation is quite expensive.
  func freeVars(_ t: TT) -> FreeVariables {
    func tryStrengthen(_ v: Var, _ s: UInt) -> Var? {
      guard s != 0 else { return v }

      if v.index > s {
        return Var(v.name, v.index - s)
      }
      return nil
    }

    /// Compute the rigid and flexible free variables present in a given
    /// expression, looking only at those variables that survive strengthening
    /// as binders are traversed.
    func go(_ strength: UInt, _ t: TT) -> FreeVariables {
      switch t {
      case let .lambda(body):
        return go(strength + 1, body)
      case let .pi(domain, codomain):
        return go(strength, domain).append(go(strength, codomain))
      case let .apply(.variable(v), elims):
        let fvs: FreeVariables
        if let sv = tryStrengthen(v, strength) {
          fvs = FreeVariables([sv], [])
        } else {
          fvs = FreeVariables([], [])
        }
        return elims.flatMap({ (t) -> [FreeVariables] in
          switch t {
          case let .apply(t):
            return [go(strength, t)]
          default:
            return []
          }
        }).reduce(fvs, { $1.append($0) })
      case let .apply(.definition(o), elims):
        let fvs1 = o.args.map({ go(strength, $0) }).reduce(FreeVariables(), {
          return $1.append($0)
        })
        return elims.flatMap({ (t) -> [FreeVariables] in
          switch t {
          case let .apply(t):
            return [go(strength, t)]
          default:
            return []
          }
        }).reduce(fvs1, { $1.append($0) })
      case let .apply(.meta(_), elims):
        let fvs = elims.flatMap({ (t) -> [FreeVariables] in
          switch t {
          case let .apply(t):
            return [go(strength, t)]
          default:
            return []
          }
        }).reduce(FreeVariables(), { $1.append($0) })
        return FreeVariables([], fvs.rigid.union(fvs.flexible))
      case .type:
        return FreeVariables()
      case .refl:
        return FreeVariables()
      default:
        fatalError()
      }
    }
    return go(0, t)
  }
}
