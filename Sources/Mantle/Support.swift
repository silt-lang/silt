/// Syntax.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Moho

public typealias Type<T> = T
public typealias Term<T> = T
public typealias Abstraction<T> = T

public typealias Closed<T> = T
public typealias Context = [(Name, Type<Expr>)]

public typealias Var = Named<UInt>

public struct Projection {
  public struct Field { let unField: UInt }

  let name: QualifiedName
  let field: Field
}

public struct Opened<K, T> {
  let key: K
  let args: [Term<T>]
}

public enum Eliminator<T> {
  case apply(T)
  case project(Opened<Projection, T>)
}

public enum Head<T> {
  case variable(Var)
  case definition(Opened<QualifiedName, T>)
  case meta(Meta)
}

enum TypeTheory<T> {
  case pi(Type<T>, Abstraction<Type<T>>)
  case lambda(Abstraction<T>)
  case type
  case constructor(Opened<QualifiedName, T>, [Term<T>])
  case apply(Head<T>, [Eliminator<T>])
  case refl(Type<T>, Term<T>, Term<T>)
}

public struct Named<T: Hashable> {
  let name: Name
  let val: T

  init(_ name: Name, _ val: T) {
    self.name = name
    self.val = val
  }
}

extension Named: Equatable, Hashable {
  public static func == (l: Named, r: Named) -> Bool {
    return l.name == r.name && l.val == r.val
  }

  public var hashValue: Int {
    return self.val.hashValue
  }
}

public final class Environment {
  var blocks: [Block]
  var pending: [(Name, Type<Expr>)]

  public init(_ ctx: Context) {
    self.blocks = [Block(ctx, [:])]
    self.pending = []
  }

  init(_ blocks: [Block], _ pending: Context) {
    self.blocks = blocks
    self.pending = pending
  }

  var asContext: Context {
    return self.pending + self.blocks.flatMap({ $0.context }).reversed()
  }

  func lookupName(_ n: Name) -> (Var, Expr)? {
    fatalError()
  }
}

struct Block {
  let context: Context
  let opened: [QualifiedName: [Term<Expr>]]

  init(_ ctx: Context, _ opened: [QualifiedName: [Term<Expr>]]) {
    self.context = ctx
    self.opened = opened
  }
}

public typealias Tel<T> = [(Name, Term<T>)]

public struct Meta: Comparable, Hashable {
  let id: Int

  public static func == (l: Meta, r: Meta) -> Bool {
    return l.id == r.id
  }

  public static func < (l: Meta, r: Meta) -> Bool {
    return l.id < r.id
  }

  public var hashValue: Int {
    return self.id
  }
}

public struct MetaBody {
  let arguments: UInt
  let body: Term<Expr>
}
