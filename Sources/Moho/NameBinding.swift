/// NameBinding.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Crust
import Lithosphere
import Foundation

#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

// MARK: Lookup

// The number of parameters.
typealias NumExplicitArguments = Int
typealias NumImplicitArguments = Int

/// Specific information about a name returned from Lookup.
public enum NameInfo {
  /// The result was a definition, retrieves the number of implicit arguments.
  case definition([ArgumentPlicity])
  /// The result was a constructor, retrieves the number of implicit and
  /// explicit arguments.
  case constructor([ArgumentPlicity])
  /// The result was a record projection, retrieves the number of implicit
  /// arguments.
  case projection
  /// The result was a module, returns its local names.
  case module(LocalNames)

  var isConstructor: Bool {
    guard case .constructor(_) = self else {
      return false
    }
    return true
  }
}

public class NameBinding {
  var activeScope: Scope
  let engine: DiagnosticEngine
  let reparser: Reparser
  let fileURL: URL
  let processImportedFile: (URL) -> LocalNames?

  var notationMap: [Scope.ScopeID: [NewNotation]] = [:]

  public init(topLevel: ModuleDeclSyntax, engine: DiagnosticEngine,
              fileURL: URL,
              processImportedFile: @escaping (URL) -> LocalNames?) {
    let moduleName = QualifiedName(ast: topLevel.moduleIdentifier)
    self.activeScope = Scope(moduleName)
    self.engine = engine
    self.reparser = Reparser(engine: engine)
    self.fileURL = fileURL
    self.processImportedFile = processImportedFile
  }

  public func performScopeCheck(topLevel: ModuleDeclSyntax) -> DeclaredModule {
    let topLevelName = QualifiedName(ast: topLevel.moduleIdentifier)
    _ = self.validateModuleName(topLevelName)
    return self.scopeCheckModule(topLevel, topLevel: true)
  }

  public var localNames: LocalNames {
    return self.activeScope.nameSpace.localNames
  }
}

#if os(Linux)
extension ObjCBool {
  // HACK: Garbage representation mismatch that is cleared up by 4.1.
  var boolValue: Bool {
    return self
  }
}
#endif

extension FileManager {
  fileprivate func casePreservingFileExists(
    atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>) -> Bool {
    let result = self.fileExists(atPath: path, isDirectory: isDirectory)
    guard result else {
      return result
    }

    guard let buffer = malloc(Int(PATH_MAX)) else {
      fatalError()
    }
    let pathRepr = self.fileSystemRepresentation(withPath: path)
    let fd = open(pathRepr, O_RDONLY)
    guard fd >= 0 else {
      fatalError("File exists but open() failed \(path)?")
    }
    var res: Int32 = 0
    repeat {
      #if os(macOS)
      res = fcntl(fd, F_GETPATH, buffer)
      #elseif os(Linux)
      guard realpath(pathRepr, buffer.assumingMemoryBound(to: Int8.self)) != nil else {
        res = -1
        continue
      }
      res = 0
      #endif
    } while res == -1 && errno == EINTR
    let fileBuffer = buffer.assumingMemoryBound(to: Int8.self)
    let fileURL = URL(fileURLWithFileSystemRepresentation: .init(fileBuffer),
                      isDirectory: isDirectory.pointee.boolValue,
                      relativeTo: nil)
    close(fd)
    free(buffer)
    return result && fileURL.path == path
  }
}

extension NameBinding {
  func validateModuleName(_ name: QualifiedName) -> URL? {
    return self.matchNameToStructure(name, true)
  }

  func validateImportName(_ name: QualifiedName) -> URL? {
    return self.matchNameToStructure(name, false)
  }

  private func matchNameToStructure(_ name: QualifiedName,
                                    _ inferDirectoryStructure: Bool) -> URL? {
    var pathBase = self.fileURL
    pathBase.deleteLastPathComponent()
    let modPath = name.module.reversed().reduce(name.name.string) { (acc, next) in
      if inferDirectoryStructure { pathBase.deleteLastPathComponent() }
      return next.string + "/" + acc
    }
    var isDir: ObjCBool = false
    let expectedPath = pathBase
                        .appendingPathComponent(modPath)
                        .appendingPathExtension("silt")
    guard
      FileManager.default.casePreservingFileExists(atPath: expectedPath.path,
                                                   isDirectory: &isDir)
    else {
      guard inferDirectoryStructure else {
        return nil
      }

      self.engine.diagnose(.incorrectModuleStructure(name),
                           node: name.node) {
        let fileName = self.fileURL.lastPathComponent
        if isDir.boolValue {
          $0.note(.unexpectedDirectory(fileName), node: name.node)
        } else {
          $0.note(.expectedModulePath(name, fileName, expectedPath.path,
                                      self.fileURL.path), node: name.node)
        }
      }
      return nil
    }
    return expectedPath
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
  func lookupLocalName(_ name: Name) -> (FullyQualifiedName, NameInfo)? {
    return lookup(in: { namespace in
      return namespace.localNames[name].map { info in
        return (QualifiedName(cons: name, namespace.module), info)
      }
    })
  }

  /// Looks up a name that has been opened into local scope, perhaps under
  /// a different name.  If there is a match, its fully-qualified name and
  /// information about that name is returned.
  func lookupOpenedName(_ n: Name) -> (FullyQualifiedName, NameInfo)? {
    guard let mbNames = self.activeScope.openedNames[n] else {
      return .none
    }

    guard mbNames.count == 1 else {
      engine.diagnose(.ambiguousName(n), node: n.syntax) {
        for cand in mbNames {
          $0.note(.ambiguousCandidate(cand))
        }
      }
      return .none
    }

    let x = mbNames[0]
    return self.lookupFullyQualifiedName(x).map { ni in (x, ni) }
  }

  /// Looks up a fully-qualified name that has been opened into this scope by
  /// traversing imported modules.  Because the fully qualified name is known,
  /// only information about that name is returned if lookup suceeds.
  func lookupFullyQualifiedName(_ n: FullyQualifiedName) -> NameInfo? {
    guard let m = n.module.first else {
      return nil
    }
    let ms = Array(n.module.dropFirst())
    let qn = QualifiedName(cons: m, ms)
    return self.activeScope.importedModules[qn].flatMap { (exports) in
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
    _ n: Name) throws -> Resolution<[ArgumentPlicity]> {
    let rln = try self.resolveLocalName(n)
    guard case let .definition(hidden) = rln.info else {
      fatalError("\(n) should be a definition")
    }
    return Resolution(qualifiedName: rln.qualifiedName, info: hidden)
  }

  /// Given the qualified name of a module, resolves it to a fully-qualified
  /// name and returns information about the contents of the module.
  func resolveModule(_ m: QualifiedName) -> Resolution<LocalNames> {
    let lkup = self.resolveQualifiedName(m)
    switch lkup {
    case let .some(.nameInfo(qn, .module(names))):
      return Resolution(qualifiedName: qn, info: names)
    case .none:
      fatalError("\(m) is not in scope")
    default:
      fatalError("\(m) should be a module")
    }
  }

  /// Given the qualified name of a constructor, resolves it to a
  /// fully-qualified name and returns information about the constructor itself.
  func resolveConstructor(
    _ m: QualifiedName) -> Resolution<[ArgumentPlicity]> {
    let lkup = self.resolveQualifiedName(m)
    switch lkup {
    case let .some(.nameInfo(qn, .constructor(plicity))):
      return Resolution(qualifiedName: qn, info: plicity)
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
  func resolveImportedModule(_ n: QualifiedName) -> Resolution<LocalNames> {
    guard let resolution = self.activeScope.importedModules[n] else {
      fatalError("\(n) should be imported")
    }
    return Resolution(qualifiedName: n, info: resolution)
  }
}

extension NameBinding {
  enum QualifiedLookupResult {
    case variable(Name)
    case nameInfo(FullyQualifiedName, NameInfo)
  }

  /// Looks up a qualified name and returns information about it.
  func resolveQualifiedName(
    _ qn: QualifiedName) -> QualifiedLookupResult? {
    let ms = Array(qn.module.dropLast())
    guard !ms.isEmpty else {
      guard !self.isBoundVariable(qn.name) else {
        return .variable(qn.name)
      }

      switch self.lookupLocalName(qn.name) {
      case let .some((qn, ni)):
        return .nameInfo(qn, ni)
      default:
        if let (qn, ni) = self.lookupOpenedName(qn.name) {
          return .nameInfo(qn, ni)
        } else {
          return .none
        }
      }
    }

    let moduleName = QualifiedName(cons: qn.module.last!, ms)
    let res = self.resolveImportedModule(moduleName)
    guard let ni = res.info[qn.name] else {
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
  func bindDefinition(
    named n: Name, _ hidden: [ArgumentPlicity]) -> FullyQualifiedName? {
    return self.bindLocal(named: n, info: .definition(hidden))
  }

  /// Bind a record projection function in the current active scope.
  func bindProjection(named n: Name) -> FullyQualifiedName? {
    return self.bindLocal(named: n, info: .projection)
  }

  /// Bind a data constructor in the current active scope.
  func bindConstructor(
    named n: Name, _ plicity: [ArgumentPlicity]) -> FullyQualifiedName? {
    return self.bindLocal(named: n, info: .constructor(plicity))
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

  func bindOpenNames(_ mapping: LocalNames, from mod: QualifiedName) {
    for (k, _) in mapping {
      guard checkNotReserved(k) && checkNotShadowing(k) else {
        continue
      }
      let qn = QualifiedName(cons: k, mod)
      self.activeScope.openedNames[k, default: []].append(qn)
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
      for name in names {
        scope.fixities[name] = fixity
      }
      return true
    }
  }

  private func checkNotReserved(_ n: Name) -> Bool {
    if Set([TokenKind.typeKeyword.text]).contains(n.string) {
      engine.diagnose(.nameReserved(n))
      return false
    }
    return true
  }

  private func checkNotShadowing(_ n: Name) -> Bool {
    return self.activeScope.vars[n] == nil && self.lookupLocalName(n) == nil
  }
}

// MARK: Action

extension NameBinding {
  /// Imports a module and binds information about its local names.
  func importModule(
    _ qn: QualifiedName,
    _ names: LocalNames) -> Bool {
    switch self.activeScope.importedModules[qn] {
    case .some(_):
      engine.diagnose(.duplicateImport(qn))
      return false
    default:
      return self.activeScope.local { scope in
        scope.importedModules[qn] = names
        return true
      }
    }
  }
}
