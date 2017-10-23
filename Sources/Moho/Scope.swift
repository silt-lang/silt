/// Scope.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere

// Indicates that a name is fully qualified.
typealias FullyQualifiedName = QualifiedName

// A mapping of module-defined names to information about that name.
typealias LocalNames = [Name: NameInfo]

// A namespace is a fully-qualified named scope into which a number of unique
// names may be placed.
struct NameSpace {
  var module: FullyQualifiedName
  // The definitions defined in some module.
  var localNames: LocalNames

  init(_ qn: FullyQualifiedName) {
    self.module = qn
    self.localNames = [:]
  }
}

// A scope under which local variables are opened and the contents of modules
// are imported.
final class Scope {
  // The variables in scope.
  var vars: [Name: TokenSyntax]
  // The namespace for the current module.
  var nameSpace: NameSpace
  // The namespaces for the parent modules.
  var parentNameSpaces: [NameSpace]
  // Mapping from "opened" names to fully qualified names.  If the mapping
  // contains multiple items then that name is ambiguous.
  var openedNames: [Name: [FullyQualifiedName]]
  // The imported modules.
  var importedModules: [FullyQualifiedName: (NumImplicitArguments, LocalNames)]

  var fixities: [Name: FixityDeclSyntax]

  init(_ n: FullyQualifiedName) {
    self.vars = [:]
    self.nameSpace = NameSpace(n)
    self.parentNameSpaces = []
    self.openedNames = [:]
    self.importedModules = [:]
    self.fixities = [:]
  }

  init(_ s: Scope) {
    self.vars = s.vars
    self.nameSpace = s.nameSpace
    self.parentNameSpaces = s.parentNameSpaces
    self.openedNames = s.openedNames
    self.importedModules = s.importedModules
    self.fixities = s.fixities
  }

  func local<T>(_ s: (Scope) throws -> T) rethrows -> T {
    return try s(self)
  }
}
