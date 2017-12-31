/// Name.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere

/// A internalized representation of an unqualified name.
public struct Name: Equatable, Comparable, Hashable, CustomStringConvertible {
  let syntax: TokenSyntax
  let string: String

  /// Create a `Name` by extracting it from a `TokenSyntax` node.
  public init(name: TokenSyntax) {
    self.syntax = name
    self.string = name.tokenKind.text
  }

  public static func == (l: Name, r: Name) -> Bool {
    return l.string == r.string
  }

  public static func < (l: Name, r: Name) -> Bool {
    return l.string < r.string
  }

  public var hashValue: Int {
    return self.string.hashValue
  }

  public var description: String {
    return self.string
  }
}

/// A sequence of unqualified names forming a unique named scope under which
/// declarations may be qualified.
public struct QualifiedName: Equatable, Hashable, CustomStringConvertible {
  let name: Name
  let module: [Name]

  public init() {
    self.name = Name(name: TokenSyntax(.identifier("")))
    self.module = []
  }

  /// Create a `QualifiedName` from a `QualifiedNameSyntax` node.
  public init(ast: QualifiedNameSyntax) {
    precondition(!ast.isEmpty)
    var mods = [Name]()
    self.name = Name(name: ast[ast.count-1].name)
    guard ast.count != 1 else {
      self.module = []
      return
    }

    for i in (0..<ast.count-2).reversed() {
      mods.append(Name(name: ast[i].name))
    }
    self.module = mods
  }

  /// Create a qualified name with no base module.
  public init(name: Name) {
    self.name = name
    self.module = []
  }

  public init(cons name: Name, _ ns: QualifiedName) {
    self.name = name
    self.module = [ns.name] + ns.module
  }

  public init(cons name: Name, _ module: [Name]) {
    self.name = name
    self.module = module
  }

  public var node: TokenSyntax {
    return self.name.syntax
  }

  public var hashValue: Int {
    return self.module.reduce(self.name.hashValue) { (acc, x) in
      return acc ^ x.hashValue
    }
  }

  public static func == (l: QualifiedName, r: QualifiedName) -> Bool {
    guard l.module.count == r.module.count else {
      return false
    }

    return zip(l.module, r.module).reduce(l.name == r.name) { (acc, x) in
      return acc && (x.0 == x.1)
    }
  }

  public var description: String {
    return self.module.reversed().reduce("") { (acc, x) in
      return acc + x.description + "."
    } + self.name.description
  }

  public var string: String {
    return self.description
  }
}
