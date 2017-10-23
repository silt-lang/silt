/// Syntax.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere

public struct DeclaredModule {
  let moduleName: QualifiedName
  let params: [([Name], Expr)]
  let namespace: NameSpace
  let decls: [Decl]
}

enum Decl {
  case ascription(TypeSignature)
  case postulate(TypeSignature)
  case dataSignature(TypeSignature)
  case recordSignature(TypeSignature)
  case function(QualifiedName, [Clause])
  case data(QualifiedName, [Name], [TypeSignature])
  case record(QualifiedName, [Name], QualifiedName, [TypeSignature])
  case module(DeclaredModule)
  case importDecl(QualifiedName, [Expr])
  case openImport(QualifiedName)
}

public struct TypeSignature {
  let name: QualifiedName
  let type: Expr
}

struct Clause {
  let patterns: [Pattern]
  let body: ClauseBody
}

enum ClauseBody {
  case empty
  case body(Expr, [Decl])
}

public indirect enum Expr: Equatable {
  case lambda(([Name], Expr), Expr)
  case pi(Name, Expr, Expr)
  case function(Expr, Expr)
  case equal(Expr, Expr, Expr)
  case apply(ApplyHead, [Elimination])
  case constructor(QualifiedName, [Expr])
  case type
  case meta
  case refl

  public static func == (l: Expr, r: Expr) -> Bool {
    switch (l, r) {
    case let (.lambda((x, tl), e), .lambda((y, tr), f)):
      return x == y && tl == tr && e == f
    case let (.pi(x, a, b), .pi(y, c, d)):
      return x == y && a == c && b == d
    case let (.function(a, b), .function(c, d)):
      return a == c && b == d
    case let (.equal(a, x, y), .equal(b, z, w)):
      return a == b && x == z && w == y
    case let (.apply(h, es), .apply(g, fs)):
      return h == g && es == fs
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
}

public enum ApplyHead: Equatable {
  case variable(Name)
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

public enum Elimination: Equatable {
  case apply(Expr)
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
}

public enum DeclaredPattern {
  case wild
  case variable(Name)
  case constructor(QualifiedName, [DeclaredPattern])
}

public enum Pattern {
  case wild
  case variable(QualifiedName)
  case constructor(QualifiedName, [Pattern])
}
