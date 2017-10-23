/// NameBinding.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Crust
import Lithosphere

// MARK: Lookup

// The number of parameters.
typealias NumExplicitArguments = Int
typealias NumImplicitArguments = Int

/// Specific information about a name returned from Lookup.
enum NameInfo {
  /// The result was a definition, retrieves the number of implicit arguments.
  case definition(NumImplicitArguments)
  /// The result was a constructor, retrieves the number of implicit and
  /// explicit arguments.
  case constructor(NumImplicitArguments, NumExplicitArguments)
  /// The result was a record projection, retrieves the number of implicit
  /// arguments.
  case projection(NumImplicitArguments)
  /// The result was a module, returns its local names.
  case module(LocalNames)

  var isConstructor: Bool {
    guard case .constructor(_, _) = self else {
      return false
    }
    return true
  }
}

public class NameBinding {
  var activeScope: Scope
  let engine: DiagnosticEngine

  public init(topLevel: ModuleDeclSyntax, engine: DiagnosticEngine) {
    self.activeScope = Scope(QualifiedName(ast: topLevel.moduleIdentifier))
    self.engine = engine
  }
}

extension NameBinding {
  /// Returns whether the given name appears bound in this scope.
  func isBoundVariable(_ n: Name) -> Bool {
    return self.activeScope.vars[n] != nil
  }

  /// Under a new scope, execute a function returning a result.
  func underScope<T>(_ s: (Scope) throws -> T) rethrows -> T {
    let oldScope = self.activeScope
    self.activeScope = Scope(self.activeScope)
    let result = try s(self.activeScope)
    self.activeScope = oldScope
    return result
  }

  /// Under an existing scope, execute a function returning a result.
  func withScope<T>(_ s : Scope, _ f : (Scope) throws -> T) rethrows -> T {
    let oldScope = self.activeScope
    self.activeScope = s
    let result = try f(self.activeScope)
    self.activeScope = oldScope
    return result
  }

  /// Traverses namespaces back-to-front looking for a match to the provided
  /// predicate.  If no namespace is suitable, this function returns `.none`.
  private func lookup<A>(in f: (NameSpace) -> A?) -> A? {
    for ns in [self.activeScope.nameSpace] + self.activeScope.parentNameSpaces {
      if let a = f(ns) {
        return .some(a)
      }
    }
    return .none
  }

  /// Looks up information about a locally-defined name.  If the name is in
  /// scope, its fully-qualified name and information about that name is
  /// returned.
  func lookupLocalName(_ n: Name) -> (FullyQualifiedName, NameInfo)? {
    return lookup(in: { ns in
      return ns.localNames[n].map { x in
        return (QualifiedName(cons: n, ns.module), x)
      }
    })
  }

  /// Looks up a name that has been opened into local scope, perhaps under
  /// a different name.  If there is a match, its fully-qualified name and
  /// information about that name is returned.
  func lookupOpenedName(_ n: Name) throws -> (FullyQualifiedName, NameInfo)? {
    guard let mbNames = self.activeScope.openedNames[n] else {
      return .none
    }

    guard mbNames.count == 1 else {
      engine.diagnose(.ambiguousName(n, mbNames))
      return .none
    }

    let x = mbNames[0]
    return self.lookupFullyQualifiedName(x).map { ni in (x, ni) }
  }

  /// Looks up a fully-qualified name that has been opened into this scope by
  /// traversing imported modules.  Because the fully qualified name is known,
  /// only information about that name is returned if lookup suceeds.
  func lookupFullyQualifiedName(_ n: FullyQualifiedName) -> NameInfo? {
    let m = n.module.first!
    let ms = Array(n.module.dropFirst())
    let qn = QualifiedName(cons: m, ms)
    return self.activeScope.importedModules[qn].flatMap { (_, exports) in
      return exports[n.name]
    }
  }
}

// MARK: Name Resolution

extension NameBinding {
  struct Resolution<T> {
    let qualifiedName: FullyQualifiedName
    let info: T
  }

  /// Resolves a locally-defined name and returns a fully-qualified name and
  /// information about that name.
  ///
  /// This function should be called if the name is known to be in scope.  It
  /// throws an exception if not.
  func resolveLocalName(_ n: Name) throws -> Resolution<NameInfo> {
    guard let mb = self.lookupLocalName(n) else {
      fatalError("\(n) is not in scope")
    }
    return Resolution(qualifiedName: mb.0, info: mb.1)
  }

  /// Resolves a locally-defined name that maps to a definition returns a
  /// fully-qualified name and information about that definition.
  ///
  /// This function should be called if the name is known to be in scope and
  /// that name resolves to a definition.  It throws an exception if not.
  func resolveLocalDefinition(
    _ n: Name) throws -> Resolution<NumImplicitArguments> {
    let rln = try self.resolveLocalName(n)
    guard case let .definition(hidden) = rln.info else {
      fatalError("\(n) should be a definition")
    }
    return Resolution(qualifiedName: rln.qualifiedName, info: hidden)
  }

  /// Given the qualified name of a module, resolves it to a fully-qualified
  /// name and returns information about the contents of the module.
  func resolveModule(_ m: QualifiedName) throws -> Resolution<LocalNames> {
    let lkup = try self.resolveQualifiedName(m)
    switch lkup {
    case let .some(.nameInfo(qn, .module(names))):
      return Resolution(qualifiedName: qn, info: names)
    case .none:
      fatalError("\(m) is not in scope")
    default:
      fatalError("\(m) should be a module")
    }
  }

  typealias ArgCount
    = (implicit: NumImplicitArguments, explicit: NumExplicitArguments)

  /// Given the qualified name of a constructor, resolves it to a
  /// fully-qualified name and returns information about the constructor itself.
  func resolveConstructor(_ m: QualifiedName) throws -> Resolution<ArgCount> {
    let lkup = try self.resolveQualifiedName(m)
    switch lkup {
    case let .some(.nameInfo(qn, .constructor(hidden, args))):
      return Resolution(qualifiedName: qn, info: (hidden, args))
    case .none:
      fatalError("\(m) is not in scope")
    default:
      fatalError("\(m) should be a constructor")
    }
  }

  /// Given the qualified name of a module that has already been imported,
  /// returns the fully-qualified name of the module and information about its
  /// contents.
  ///
  /// If the named module is not in scope, or has not been previously imported,
  /// this function throws an exception.  Be sure that `importModule` has been
  /// called.
  func resolveImportedModule(
    _ n: QualifiedName) throws -> Resolution<LocalNames> {
    let resolved = try self.resolveModule(n)
    if self.activeScope.importedModules[resolved.qualifiedName] == nil {
      fatalError("\(n) should be imported")
    }
    return resolved
  }
}

extension NameBinding {
  enum QualifiedLookupResult {
    case variable(Name)
    case nameInfo(FullyQualifiedName, NameInfo)
  }

  /// Looks up a qualified name and returns information about it.
  private func resolveQualifiedName(
    _ qn: QualifiedName) throws -> QualifiedLookupResult? {
    let ms = Array(qn.module.dropFirst())
    guard !ms.isEmpty else {
      if self.isBoundVariable(qn.name) {
        return .variable(qn.name)
      } else {
        switch self.lookupLocalName(qn.name) {
        case let .some((qn, ni)):
          return .nameInfo(qn, ni)
        default:
          let res = try self.lookupOpenedName(qn.name)
          if let (qn, ni) = res {
            return .nameInfo(qn, ni)
          } else {
            return .none
          }
        }
      }
    }

    let res = try self.resolveImportedModule(QualifiedName(cons: qn.name, ms))
    guard let ni = res.info[res.qualifiedName.name] else {
      return .none
    }
    return .nameInfo(QualifiedName(cons: qn.name, res.qualifiedName), ni)
  }
}

// MARK: Binding

extension NameBinding {
  /// Qualify a name with the module of the current active scope.
  func qualify(name: Name) -> FullyQualifiedName {
    return QualifiedName(cons: name, self.activeScope.nameSpace.module)
  }

  /// Bind a local definition in the current active scope.  Suitable for types,
  /// constructors, and functions.
  ///
  /// FIXME: Break this up?
  func bindDefinition(
    named n: Name, _ hidden: NumImplicitArguments) -> FullyQualifiedName? {
    return self.bindLocal(named: n, info: .definition(hidden))
  }

  /// Bind a record projection function in the current active scope.
  func bindProjection(
    named n: Name, _ hidden: NumImplicitArguments) -> FullyQualifiedName? {
    return self.bindLocal(named: n, info: .projection(hidden))
  }

  /// Bind a local variable in the current active scope.
  ///
  /// This function checks if the variable name is not in a list of reserved
  /// names.  If it is, the name is diagnosed.
  func bindVariable(named n: Name) -> Name? {
    guard checkNotReserved(n) else {
      return nil
    }

    return self.activeScope.local { scope in
      scope.vars[n] = n.syntax
      return n
    }
  }

  /// Binds a local variable and information about that variable in the current
  /// active scope.
  ///
  /// This function checks if the variable name is reserved or previously
  /// declared in some scope.  If either of these is the case, the name is
  /// diagnosed.
  func bindLocal(named n: Name, info ni: NameInfo) -> FullyQualifiedName? {
    guard checkNotReserved(n) && checkNotShadowing(n) else {
      return nil
    }

    return self.activeScope.local { scope in
      scope.nameSpace.localNames[n] = ni
      return self.qualify(name: n)
    }
  }

  func bindFixity(_ fixity: FixityDeclSyntax) -> Bool {
    return self.activeScope.local { scope in
      let names: [Name]
      switch fixity {
      case let fixity as NonFixDeclSyntax:
        names = fixity.names.map(Name.init(name:))
      case let fixity as RightFixDeclSyntax:
        names = fixity.names.map(Name.init(name:))
      case let fixity as LeftFixDeclSyntax:
        names = fixity.names.map(Name.init(name:))
      default:
        fatalError()
      }
      for i in 0..<names.count {
        let n = names[i]
        scope.fixities[n] = fixity
      }
      return true
    }
  }

  private func checkNotReserved(_ n: Name) -> Bool {
    if Set(["Type"]).contains(n.string) {
      engine.diagnose(.nameReserved(n))
      return false
    }
    return true
  }

  private func checkNotShadowing(_ n: Name) -> Bool {
    if self.activeScope.vars[n] != nil {
      engine.diagnose(.nameShadows(n))
      return false
    }
    if let (qn, _) = self.lookupLocalName(n) {
      engine.diagnose(.nameShadows(n, local: qn))
      return false
    }
    return true
  }
}

// MARK: Action

extension NameBinding {
  /// Imports a module and binds information about its local names.
  func importModule(
    _ qn: QualifiedName,
    _ hidden: NumImplicitArguments,
    _ names: LocalNames) -> Bool {
    switch self.activeScope.importedModules[qn] {
    case .some(_):
      engine.diagnose(.duplicateImport(qn))
      return false
    default:
      return self.activeScope.local { scope in
        scope.importedModules[qn] = (hidden, names)
        return true
      }
    }
  }
}
