/// Support.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Moho

// MARK: Useful Type(aliases)

/// Marks its argument as being a type.
public typealias Type<T> = T
/// Marks its argument as being a term.
public typealias Term<T> = T
/// Marks its argument as an abstraction in a lambda term.
public typealias Abstraction<T> = T

/// A Context is a backwards list of named terms, each scoped over all
/// the previous ones.
public typealias Context = [(Name, Type<TT>)]

// A telescope is a list of binding names and their types.
public typealias Telescope<T> = [(Name, Term<T>)]

/// A `Var` is a de Bruijn-indexed and a user-provided name.
public typealias Var = Named<UInt>

/// The type of names of bound terms in a locally nameless representation.
///
/// Two names in a term are considered equal when they have the same index, but
/// not necessarily the same name. This induces alpha equivalence on
/// terms in general.
public struct Named<I: Hashable>: Equatable, Hashable, CustomStringConvertible {
  public let name: Name
  public let index: I

  public init(_ name: Name, _ val: I) {
    self.name = name
    self.index = val
  }

  public static func == (l: Named, r: Named) -> Bool {
    return l.index == r.index
  }

  public var hashValue: Int {
    return self.index.hashValue
  }

  public var description: String {
    return self.name.description + "\(self.index.hashValue)"
  }
}

extension Named where I: Numeric & Comparable {
  func weaken(_ from: I, by: I) -> Named<I> {
    return Named(self.name, self.index >= from ? self.index + by: self.index)
  }

  func strengthen(_ from: I, by: I) -> Named<I>? {
    guard self.index >= from + by else {
      return nil
    }

    return Named(self.name, self.index >= from ? (self.index - by): self.index)
  }
}

// MARK: Marker Types

/// Marks a keyed name that has been opened into scope by the type checker.
public struct Opened<K, T> {
  let key: K
  let args: [Term<T>]

  init(_ key: K, _ args: [Term<T>]) {
    self.key = key
    self.args = args
  }

  // Re-key the opened value by another key.
  func reKey<L>(_ f: (K) -> L) -> Opened<L, T> {
    return Opened<L, T>(f(self.key), self.args)
  }
}

// MARK: Definitions

/// Marks a definition as depending on a telescope of indices.
///
/// Every term may be lifted to a contextual term - in the trivial case one has
/// an empty telescope.
public struct Contextual<T, A> {
  let telescope: Telescope<T>
  let inside: A
}

public typealias Module = Contextual<TT, Set<QualifiedName>>
public typealias ContextualDefinition = Contextual<TT, Definition>
public typealias ContextualType = Contextual<TT, Type<TT>>

/// Represents a well-scoped definition.
public enum Definition {
  public enum Constant {
    /// A type ascription representing a postulate - a constant term with no
    /// body that thus contains no proof to lower.
    case postulate
    /// A data declaration with the given list of names of constructors.
    case data([QualifiedName])
    /// A record declaration with a given name and field projections.
    case record(QualifiedName, [Projection])
    /// A function, possibly invertible.
    case function(Instantiability)
  }

  case constant(Type<TT>, Constant)
  case dataConstructor(QualifiedName, UInt, Contextual<TT, Type<TT>>)
  case module(Module)
}

/// The type of definitions opened into the signature by the type checker.
public enum OpenedDefinition {
  public enum Constant {
    /// A type ascription representing a postulate - a constant term with no
    /// body that thus contains no proof to lower.
    case postulate
    /// A data declaration with the given list of names of constructors.
    case data([Opened<QualifiedName, TT>])
    /// A record declaration with a given name and field projections.
    case record(Opened<QualifiedName, TT>, [Opened<Projection, TT>])
    /// A function, possibly invertible.
    case function(Instantiability)
  }

  case constant(Type<TT>, Constant)
  case dataConstructor(Opened<QualifiedName, TT>, UInt, ContextualType)
  case module(Module)
}

// MARK: Expressions

// swiftlint:disable type_name
public typealias TT = TypeTheory<Expr>

/// The form of terms in the core language, TT.  Indexed by a type `T` for an
/// AST for user-provided expression.
public indirect enum TypeTheory<T>: Equatable, CustomStringConvertible {
  /// The type of types.
  ///
  /// FIXME: Impredicativity Bites
  case type
  /// A dependent function space.
  case pi(Type<TypeTheory<T>>, Abstraction<Type<TypeTheory<T>>>)
  /// A lambda term binding a single (unnamed) argument yielding a body term.
  case lambda(Abstraction<TypeTheory<T>>)
  /// The type of (intensional) equalities of terms.
  case refl
  /// The term-level representation of an (intensional) equality of terms.
  case equal(Type<TypeTheory<T>>, Term<TypeTheory<T>>, Term<TypeTheory<T>>)
  /// A (data) type constructor.
  case constructor(Opened<QualifiedName, TypeTheory<T>>, [Term<TypeTheory<T>>])
  /// The spine-form of an application of eliminators to a head.
  case apply(Head<TypeTheory<T>>, [Elim<TypeTheory<T>>])

  /// Deep syntactic equality of terms.
  public static func == (l: TypeTheory<T>, r: TypeTheory<T>) -> Bool {
    switch (l, r) {
    case let (.lambda(e), .lambda(f)):
      return e == f
    case let (.pi(lhsDom, lhsCod), .pi(rhsDom, rhsCod)):
      return lhsDom == rhsDom && lhsCod == rhsCod
    case let (.equal(lhsEqTy, lhsTm1, lhsTm2), .equal(rhsEqTy, rhsTm1, rhsTm2)):
      return lhsEqTy == rhsEqTy && lhsTm1 == rhsTm1 && rhsTm2 == lhsTm2
    case let (.apply(lhsHead, lhsElims), .apply(rhsHead, rhsElims)):
      return lhsHead == rhsHead && lhsElims == rhsElims
    case let (.constructor(lhsName, lhsArgs), .constructor(rhsName, rhsArgs)):
      return (lhsName.key == rhsName.key)
         && zip(lhsName.args, rhsName.args).reduce(true, { acc, t in
        let (l, r) = t
        return acc && (l == r)
      }) && zip(lhsArgs, rhsArgs).reduce(true, { acc, t in
        let (l, r) = t
        return acc && (l == r)
      })
    case (.type, .type):
      return true
    case (.refl, .refl):
      return true
    default:
      return false
    }
  }

  public var description: String {
    switch self {
    case .refl:
      return "refl"
    case .type:
      return "Type"
    case let .pi(.pi(llhs, lrhs), rhs):
      return "(\(llhs) -> \(lrhs)) -> \(rhs)"
    case let .pi(lhs, rhs):
      return "\(lhs) -> \(rhs)"
    case let .lambda(body):
      return "λ _ -> \(body)"
    case let .equal(eqTy, lhs, rhs):
      return "\(lhs) =(\(eqTy))= \(rhs)"
    case let .constructor(openTm, args):
      let argDesc = args.map({ $0.description }).joined(separator: ", ")
      return "\(openTm.key)(\(argDesc))"
    case let .apply(head, elims):
      switch head {
      case let .definition(def):
        guard !elims.isEmpty else { return "\(def.key)" }
        let argDesc = elims.map({ $0.description }).joined(separator: ", ")
        return "\(def.key)[\(argDesc)]"
      case let .meta(meta):
        guard !elims.isEmpty else { return "\(meta)" }
        let elimDesc = elims.map({ $0.description }).joined(separator: ", ")
        return "\(meta)[\(elimDesc)]"
      case let .variable(vari):
        guard !elims.isEmpty else { return "\(vari.name)@\(vari.index)" }
        let elimDesc = elims.map({ $0.description }).joined(separator: ", ")
        return "\(vari.name)[\(elimDesc)]"
      }
    }
  }
}

/// The head of the spine-form of an application.
public enum Head<T: Equatable>: Equatable {
  /// The head is a local variable.
  ///
  /// E.g. The `f` and `g` terms in:
  ///
  /// ```
  /// s f g x y = f x (g y)
  /// ```
  case variable(Var)
  /// The head is a definition opened by the type checker.
  ///
  /// E.g. The `cons` in:
  ///
  /// ```
  /// c x xs = (cons x xs)
  /// ```
  case definition(Opened<QualifiedName, T>)
  /// The head is a metavariable.
  case meta(Meta)

  public static func == (l: Head<T>, r: Head<T>) -> Bool {
    switch (l, r) {
    case let (.variable(n), .variable(m)):
      return n == m
    case let (.definition(e), .definition(f)):
      return e.key == f.key && zip(e.args, f.args).reduce(true) { (acc, t) in
        let (etm, ftm) = t
        return acc && (etm == ftm)
      }
    case let (.meta(e), .meta(f)):
      return e == f
    default:
      return false
    }
  }
}

/// An elimination for an expression.
public enum Elim<T: Equatable>: Equatable, CustomStringConvertible {
  /// Apply an expression to the nearest bindable thing on hand.
  case apply(T)
  /// Project the named field from a record.
  case project(Opened<Projection, T>)

  public static func == (l: Elim<T>, r: Elim<T>) -> Bool {
    switch (l, r) {
    case let (.apply(e), .apply(f)):
      return e == f
    case let (.project(n), .project(m)):
      return n.key == m.key && zip(n.args, m.args).reduce(true) { (acc, t) in
        let (lhs, rhs) = t
        return acc && (lhs == rhs)
      }
    default:
      return false
    }
  }

  public var description: String {
    switch self {
    case let .apply(arg):
      return "\(arg)"
    case let .project(proj):
      return "#\(proj.key.name)"
    }
  }

  /// If this is an application, retrieve the term associated with it.
  /// `nil` otherwise.
  public var applyTerm: T? {
    switch self {
    case let .apply(tm): return .some(tm)
    default: return nil
    }
  }

  /// If this is a projection, retrieve the field associated with it.
  /// `nil` otherwise.
  public var projectTerm: Opened<Projection, T>? {
    switch self {
    case let .project(tm): return .some(tm)
    default: return nil
    }
  }
}

// MARK: Environment

/// The environment is a tiered mapping from names to types. The current
/// environment may be suspended inside a block when subproblems are solved to
/// avoid the interaction of fresh contexts.
///
/// - seealso: TypeChecker.underNewScope(_:)
public final class Environment {
  /// A `Scope` is a suspension of a working context.
  public class Scope {
    let context: Context
    var opened: [QualifiedName: [Term<TT>]]

    init(_ ctx: Context, _ opened: [QualifiedName: [Term<TT>]]) {
      self.context = ctx
      self.opened = opened
    }
  }
  
  var scopes: [Scope]
  var context: Context

  /// Initialize a fresh environment with a starting block and context.
  public init(_ ctx: Context) {
    self.scopes = [Scope(ctx, [:])]
    self.context = []
  }

  /// Returns whether this context and all of its blocks are empty.
  public var isEmpty: Bool {
    return self.asContext.isEmpty
  }

  /// Retrieves the environment as one contiguous context with the current
  /// context at the fore and subsequent blocks in LIFO order in back.
  public var asContext: Context {
    return self.context + self.scopes.reversed().flatMap({ $0.context })
  }

  /// Returns an array containing the result of mapping the given function
  /// across the all variables in all scopes in the environment.
  func forEachVariable<T>(_ f: (Var) -> T) -> [T] {
    let ctx = self.asContext
    var result = [T]()
    result.reserveCapacity(ctx.count)
    for (ix, (n, _)) in ctx.enumerated() {
      result.append(f(Var(n, UInt(ix))))
    }
    return result
  }

  /// Looks up a name in the current environment.  If no such entry exists,
  /// the result is `nil`.
  ///
  /// The returned variable contains the appropriate de Bruijn index for the
  /// associated term.
  func lookupName(_ name: Name, _ elim: (TT, [Elim<TT>]) -> TT) -> (Var, TT)? {
    guard !self.isEmpty else {
      return nil
    }

    var ix = UInt(0)
    for (n, ty) in self.asContext.reversed() {
      defer { ix += 1 }
      guard name != n else {
        return (Var(name, ix), ty.applySubstitution(.weaken(Int(ix) + 1), elim))
      }
    }
    return nil
  }

  /// Looks up a de Bruijn-indexed variable in the current environment.  If no
  /// such entry exists, the result is `nil`.
  func lookupVariable(_ v: Var, _ elim: (TT, [Elim<TT>]) -> TT) -> TT? {
    let ctx = self.asContext
    if v.index > UInt(ctx.count) {
      return nil
    }
    let type = ctx[ctx.count - Int(v.index) - 1].1
    return type.applySubstitution(.weaken(Int(v.index + 1)), elim)
  }

  @available(*, deprecated, message: "Only for use in the debugger!")
  func dump() {
    print("=========ENVIRONMENT=========")
    for (v, ty) in self.asContext {
      print("(", v, ": ", ty.description, ")")
    }
    print("=============================")
  }
}

// MARK: Metas

/// A `Meta` represents a metavariable created during the elaboration and
/// solving processes.
///
/// A metavariable may stand for one term (modulo convertibility) in a
/// well-formed typing context.  Hence, the signature built during the solving
/// process maintains a mapping from solved metas to the terms they represent.
///
/// Metavariables are uniquely identified by an internal identification number.
public struct Meta: Comparable, Hashable, CustomStringConvertible {
  /// A `Binding` represents the term associated with a particular metavariable.
  public struct Binding {
    /// The arity of the given binding.
    let arity: Int
    private let body: TT

    init(arity: Int, body: TT) {
      self.arity = arity
      self.body = body
    }

    /// Returns the body of the metavariable binding as a TT term.
    var internalize: TT {
      var tm: TT =  self.body
      for _ in 0..<self.arity {
        tm = TT.lambda(tm)
      }
      return tm
    }
  }

  private let id: Int

  /// Create a metavariable with the given unique identifier.
  init(_ id: Int) {
    self.id = id
  }

  public static func == (l: Meta, r: Meta) -> Bool {
    return l.id == r.id
  }

  public static func < (l: Meta, r: Meta) -> Bool {
    return l.id < r.id
  }

  public var hashValue: Int {
    return self.id
  }

  public var description: String {
    return "$\(self.id)"
  }
}

// MARK: Patterns

public enum Pattern {
  case variable
  case constructor(Opened<QualifiedName, TT>, [Pattern])
}

// MARK: Records

public struct Projection: Equatable {
  public struct Field: Equatable {
    let unField: Int

    public static func == (l: Field, r: Field) -> Bool {
      return l.unField == r.unField
    }
  }

  let name: QualifiedName
  let field: Field

  public static func == (l: Projection, r: Projection) -> Bool {
    return l.name == r.name && l.field == r.field
  }
}

// MARK: Clauses

public struct Clause {
  let pattern: [Pattern]
  let body: Term<TT>

  var boundCount: Int {
    return self.pattern.reduce(0) { (acc, next) in
      switch next {
      case .variable:
        return 1 + acc
      case .constructor(_, let pats):
        return acc + Clause(pattern: pats, body: TT.type).boundCount
      }
    }
  }
}

//
public enum Instantiability {
  case open
  case invertible(Invertibility)

  // An function has invertible clauses if all heads mentioned in the initial
  // pattern are distinct and the constructors are injective.
  public enum Invertibility {
    case notInvertible([Clause])
    case invertible([Clause])

    var ignoreInvertibility: [Clause] {
      switch self {
      case let .notInvertible(cs): return cs
      case let .invertible(cs): return cs
      }
    }

    public enum TermHead: Hashable {
      case pi
      case definition(QualifiedName)

      public static func == (lhs: TermHead, rhs: TermHead) -> Bool {
        switch (lhs, rhs) {
        case (.pi, .pi): return true
        case let (.definition(n1), .definition(n2)): return n1 == n2
        default: return false
        }
      }

      public var hashValue: Int {
        switch self {
        case .pi: return "".hashValue
        case let .definition(n): return n.hashValue
        }
      }
    }
  }
}
