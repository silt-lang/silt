/// Syntax.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere

/// Represents a module declared in source with child declarations that are all
/// known to be well-scoped.
public struct DeclaredModule {
  /// The name of the module.
  public let moduleName: QualifiedName
  /// The parameter list of the module, in user-declared order.
  public let params: [DeclaredParameter]
  /// The namespace of the module.
  let namespace: NameSpace
  /// The child declarations.
  public let decls: [Decl]
}

/// Represents a well-scoped declaration.
public enum Decl {
  /// A type ascription.
  ///
  /// ```
  /// x y z : forall {A B : Type} -> A -> (B -> ...
  /// ```
  case ascription(TypeSignature)
  /// A type ascription representing a postulate - a constant term with no body
  /// that thus contains no proof to lower.  Code referencing postulates will
  /// crash when evaluated at runtime, but will succeed when normalized at
  /// compile-time.
  ///
  /// ```
  /// postulate
  ///   extensionality : forall {S : Type}{T : S -> Type}
  ///                           (f g : (s : S) -> T s) ->
  ///                           ((s : S) -> f s ≃ g s) -> f ≃ g
  /// ```
  case postulate(TypeSignature)
  /// A type ascription representing a data declaration.
  ///
  /// E.g. this portion of the standard definition of
  /// the Peano naturals:
  ///
  /// ```
  /// data N : Type where
  /// ```
  case dataSignature(TypeSignature)
  /// A type ascription representing a record declaration and the record's
  /// constructor.
  ///
  /// E.g. this portion of a record:
  ///
  /// ```
  /// record Person : Type where
  ///   constructor MkPerson
  /// ```
  case recordSignature(TypeSignature, QualifiedName)
  /// The body of a function with clauses attached.
  ///
  /// The signature of the function is not immediately available, but may be
  /// acquired by querying the context with the qualified name.
  case function(QualifiedName, [DeclaredClause])
  /// The body of a data declaration.
  ///
  /// E.g. this portion of the standard definition of
  /// the Peano naturals:
  ///
  /// ```
  ///   | Z : N
  ///   | S : N -> N
  /// ```
  ///
  /// The signature of the parent data declaration is not immediately available,
  /// but may be acquired by querying the context with the qualified name.
  case data(QualifiedName, [Name], [TypeSignature])
  /// The body of a record declaration.
  ///
  /// The signature of the parent record declaration is not immediately
  /// available, but may be acquired by querying the context with the
  /// qualified name.
  case record(QualifiedName, [Name], QualifiedName, [TypeSignature])
  /// A module declaration.
  ///
  /// ```
  /// module Foo where
  /// ```
  case module(DeclaredModule)
  /// An import declaration that brings module-qualified names into the current
  /// scope.
  case importDecl(QualifiedName, [Expr])
  /// An open-and-import declaration that brings module-qualified names as well
  /// as unqualified open names into the current scope.
  ///
  /// Declarations that have been opened appear in scope as though they were
  /// defined in the current module.  By now, any conflicts this might cause
  /// have been resolved by Scope Check.
  case openImport(QualifiedName)
  /// A function declaration without a signature in a `let` binding.
  ///
  /// ```
  /// let x = 4 + 5 in x
  /// ```
  case letBinding(QualifiedName, DeclaredClause)
}

/// Represents a used-declared parameter - a list of names, an ascription
/// expression, and whether it is implicit or explicit.
public struct DeclaredParameter {
  /// The names bound by this parameter.
  public let names: [Name]
  /// The type ascription for this parameter.
  public let ascription: Expr
  /// Whether this parameter is implicit or explicit.
  public let plicity: ArgumentPlicity

  public init(_ names: [Name], _ ascription: Expr, _ plicity: ArgumentPlicity) {
    self.names = names
    self.ascription = ascription
    self.plicity = plicity
  }
}

/// Represents information about whether a parameter is implicit or explicit.
public enum ArgumentPlicity {
  /// The parameter is explicit.
  case explicit
  /// The parameter is implicit.
  case implicit
}

/// Represents a type signature - a name and an expression.
public struct TypeSignature {
  public let name: QualifiedName
  public let type: Expr
  public let plicity: [ArgumentPlicity]
}

/// Represents a clause in a pattern.
public struct DeclaredClause: CustomStringConvertible {
  public let patterns: [DeclaredPattern]
  public let body: Body

  /// Represents the body of a clause.
  public enum Body {
    /// A function clause may have an empty body if a clause introduces an
    /// absurd pattern.
    case empty
    /// A normal function body.
    case body(Expr, [Decl])

    public var expr: Expr? {
      guard case .body(let e, _) = self else { return nil }
      return e
    }
  }

  public var description: String {
    let patternDescription
      = self.patterns.map({ $0.description }).joined(separator: " ")
    switch self.body {
    case .empty:
      return "\(patternDescription) = ()"
    case let .body(expr, _):
      return "\(patternDescription) = \(expr)"
    }
  }
}

/// Represents an intermediate pattern that better conveys structure than the
/// syntax tree.
public enum DeclaredPattern: CustomStringConvertible {
  /// A wildcard pattern.
  ///
  /// ```
  /// foo _ _ _ = ...
  /// ```
  case wild
  /// A variable pattern.
  ///
  /// ```
  /// foo x y z = ...
  /// ```
  case variable(Name)
  /// A constructor pattern.
  ///
  /// ```
  /// foo [] x y          = ...
  /// foo (_::_ x xs) y z = ...
  /// ```
  case constructor([QualifiedName], [DeclaredPattern])
  /// An uninhabited pattern.
  ///
  /// ```
  /// foo [] ()          = ...
  /// foo (_::_ x xs) () = ...
  /// ```
  case absurd(AbsurdExprSyntax)

  public var name: Name? {
    switch self {
    case .variable(let name): return name
    case .wild:
      return Name(name: SyntaxFactory.makeToken(.identifier("_"),
                                                presence: .implicit))
    case .constructor(_, _): return nil
    case .absurd:
      return Name(name: SyntaxFactory.makeToken(.identifier("()"),
                                                presence: .implicit))
    }
  }

  public var description: String {
    switch self {
    case .wild: return "_"
    case let .variable(name): return name.description
    case let .constructor(constrName, pats):
      return
        """
        \(constrName)(\(pats.map({ $0.description }).joined(separator: ", ")))
        """
    case .absurd(_): return "()"
    }
  }
}

/// Represents an intermediate record field.
public struct DeclaredField {
  public let signature: TypeSignature
}


/// Expressions - well-scoped but not necessarily well-formed.
public indirect enum Expr: Equatable, CustomStringConvertible {
  /// An application of a head to a body of eliminators.
  ///
  /// The head may by a local variable or a definition while the eliminators
  /// are either applications or projections.  The idea is that one form of
  /// a neutral term is the case where we have no eliminators left to apply.
  /// This also means that we do not need an explicit case for variables (yet) -
  /// a variable is just a `variable` head applied to no eliminators.
  case apply(ApplyHead, [Elimination])
  /// A dependent function, or Π, type.
  ///
  /// A pi type captures a dependent function space mapping terms from its
  /// domain to terms in its codomain that may depend on the terms of the
  /// domain.
  case pi(Name, Expr, Expr)
  /// The "traditional" non-dependent function space.
  case function(Expr, Expr)
  /// A lambda binding some variables of the same type to some output expression
  /// that may depend on those variables.
  case lambda((Name, Expr), Expr)
  /// A type constructor for a term.
  case constructor(QualifiedName, [QualifiedName], [Expr])
  /// The "Type" sort.
  ///
  /// Yeah, it's probably not a good idea to call a sort "Type", but it's better
  /// than "Set".
  case type
  /// A representation of a metavariable - an unknown expression that requires
  /// the aid of the type checker to determine.
  ///
  /// In a dependently-typed setting, we are not restricted to merely binding
  /// types to metas.  Because types and terms are the same thing, we may engage
  /// in proof search in order to determine a program that inhabits a type, or a
  /// type that corresponds to a program - (Both is out of scope).
  case meta
  /// A term representing a proof of equality between two terms of one
  /// particular type.
  ///
  /// Silt terms take an intensional view of equality meaning we need little
  /// more than to check deep syntactic equality of terms (after a little
  /// reduction) to declare that they are equal.  This also means it can be
  /// a pain in the neck to try to prove anything outside of the ensemble of
  /// constructors you have to work with.
  ///
  /// For a discussion of intensionality and extensionality, see
  /// Hillary Putnam's ["The Meaning of Meaning"](www.goo.gl/W42JBa).
  case equal(Expr, Expr, Expr)
  /// Represents `refl`, the only inhabitant of the proof of intensional
  /// equality of terms.
  case refl

  /// Represents a `let` binding of the form
  ///
  /// ```
  /// let <decl>+ in <expr>
  /// ```
  case `let`([Decl], Expr)

  /// Deep syntactic equality of terms.
  public static func == (l: Expr, r: Expr) -> Bool {
    switch (l, r) {
    case let (.lambda((lhsBind, lhsBody), e), .lambda((rhsBind, rhsBody), f)):
      return lhsBind == rhsBind && lhsBody == rhsBody && e == f
    case let (.pi(lhsBind, lhsDom, lhsCod), .pi(rhsBind, rhsDom, rhsCod)):
      return lhsBind == rhsBind && lhsDom == rhsDom && lhsCod == rhsCod
    case let (.function(lhsDom, lhsCod), .function(rhsDom, rhsCod)):
      return lhsDom == rhsDom && lhsCod == rhsCod
    case let (.equal(lhsEqTy, lhsTm1, lhsTm2), .equal(rhsEqTy, rhsTm1, rhsTm2)):
      return lhsEqTy == rhsEqTy && lhsTm1 == rhsTm1 && rhsTm2 == lhsTm2
    case let (.apply(lhsHead, lhsElims), .apply(rhsHead, rhsElims)):
      return lhsHead == rhsHead && lhsElims == rhsElims
    case (.type, .type):
      return true
    case (.meta, .meta):
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
    case let .pi(name, .pi(iname, llhs, lrhs), rhs):
      return "(\(name) : (\(iname) : \(llhs) -> \(lrhs))) -> \(rhs)"
    case let .pi(name, lhs, rhs):
      return "(\(name) : \(lhs)) -> \(rhs)"
    case let .function(.function(llhs, lrhs), rhs):
      return "(\(llhs) -> \(lrhs)) -> \(rhs)"
    case let .function(lhs, rhs):
      return "\(lhs) -> \(rhs)"
    case .meta:
      return "$META"
    case let .lambda((name, ty), body):
      return "λ (\(name) : \(ty)) . \(body)"
    case let .let(decls, expr):
      let declDesc = decls.map { "\($0)" }.joined(separator: "; ")
      return "let \(declDesc) in \(expr)"
    case let .equal(eqTy, lhs, rhs):
      return "\(lhs) =(\(eqTy))= \(rhs)"
    case let .constructor(_, openTm, args):
      return "\(openTm)(\(args.map({$0.description}).joined(separator: ", ")))"
    case let .apply(head, elims):
      switch head {
      case let .definition(def):
        guard !elims.isEmpty else { return "\(def)" }
        return "\(def)[\(elims.map({$0.description}).joined(separator: ", "))]"
      case let .variable(vari):
        guard !elims.isEmpty else { return "\(vari)" }
        return "\(vari)[\(elims.map({$0.description}).joined(separator: ", "))]"
      }
    }
  }
}

/// Represents the "head" of an application expression.
public enum ApplyHead: Equatable {
  /// The head is a local variable.
  ///
  /// E.g. The `f` and `g` terms in:
  ///
  /// ```
  /// s f g x y = f x (g y)
  /// ```
  case variable(Name)
  /// The head is a definition.
  ///
  /// E.g. The `List` in:
  ///
  /// ```
  /// f A = List A
  /// ```
  case definition(QualifiedName)

  public static func == (l: ApplyHead, r: ApplyHead) -> Bool {
    switch (l, r) {
    case let (.variable(n), .variable(m)):
      return n == m
    case let (.definition(e), .definition(f)):
      return e == f
    default:
      return false
    }
  }
}

/// An elimination for an expression.
public enum Elimination: Equatable, CustomStringConvertible {
  /// Apply an expression to the nearest bindable thing on hand.
  case apply(Expr)
  /// Project the named field from a record.
  case projection(QualifiedName)

  public static func == (l: Elimination, r: Elimination) -> Bool {
    switch (l, r) {
    case let (.apply(e), .apply(f)):
      return e == f
    case let (.projection(n), .projection(m)):
      return n == m
    default:
      return false
    }
  }

  public var description: String {
    switch self {
    case let .apply(arg):
      return "\(arg)"
    case let .projection(proj):
      return "#\(proj)"
    }
  }
}
