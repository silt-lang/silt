/// Scope.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere

// Indicates that a name is fully qualified.
public typealias FullyQualifiedName = QualifiedName

// A mapping of module-defined names to information about that name.
public typealias LocalNames = [Name: NameInfo]

// A namespace is a fully-qualified named scope into which a number of unique
// names may be placed.
final class NameSpace {
  var module: FullyQualifiedName
  // The definitions defined in some module.
  var localNames: LocalNames

  weak var parent: NameSpace?

  init(_ qn: FullyQualifiedName, parent: NameSpace?) {
    self.module = qn
    self.localNames = [:]
    self.parent = parent
  }
}

// A scope under which local variables are opened and the contents of modules
// are imported.
final class Scope {
  // The variables in scope.
  var vars: [Name: TokenSyntax]
  // The namespace for the current module.
  var nameSpace: NameSpace
  // Mapping from "opened" names to fully qualified names.  If the mapping
  // contains multiple items then that name is ambiguous.
  var openedNames: [Name: [FullyQualifiedName]]
  // The imported modules.
  var importedModules: [FullyQualifiedName: LocalNames]

  var fixities: [Name: FixityDeclSyntax]

  typealias ScopeID = UInt
  let scopeID: ScopeID

  private static var scopeIDPool: UInt = 0

  init(rooted n: FullyQualifiedName) {
    defer { Scope.scopeIDPool += 1 }
    self.scopeID = Scope.scopeIDPool
    self.vars = [:]
    self.nameSpace = NameSpace(n, parent: nil)
    self.openedNames = [:]
    self.importedModules = [:]
    self.fixities = [:]
  }

  init(cons s: Scope, _ name: FullyQualifiedName? = nil) {
    self.scopeID = s.scopeID
    self.vars = s.vars
    self.nameSpace = NameSpace(name ?? s.nameSpace.module, parent: s.nameSpace)
    self.openedNames = s.openedNames
    self.importedModules = s.importedModules
    self.fixities = s.fixities
  }

  func local<T>(_ s: (Scope) throws -> T) rethrows -> T {
    return try s(self)
  }

  /// Qualify a name with the module of the current scope.
  func qualify(name: Name) -> FullyQualifiedName {
    return QualifiedName(cons: name, self.nameSpace.module)
  }
}
