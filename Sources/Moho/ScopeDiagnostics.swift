/// ScopeDiagnostics.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere

extension Diagnostic.Message {
  static func undeclaredIdentifier(_ n: QualifiedName) -> Diagnostic.Message {
    return Diagnostic.Message(.error, "use of undeclared identifier '\(n)'")
  }

  static func undeclaredIdentifier(_ n: Name) -> Diagnostic.Message {
    return Diagnostic.Message(.error, "use of undeclared identifier '\(n)'")
  }

  static func ambiguousName(_ n: Name) -> Diagnostic.Message {
    return Diagnostic.Message(.error, "ambiguous use of name '\(n)'")
  }

  static func ambiguousCandidate(_ n: FullyQualifiedName) -> Diagnostic.Message {
    return Diagnostic.Message(.note, "candidate has name '\(n)")
  }

  static func nameReserved(_ n: Name) -> Diagnostic.Message {
    return Diagnostic.Message(.error, "cannot use reserved name '\(n)'")
  }

  static func nameShadows(_ n: Name) -> Diagnostic.Message {
    return Diagnostic.Message(.error, "cannot shadow name '\(n)'")
  }

  static func nameShadows(
    _ local: Name, _ n: FullyQualifiedName) -> Diagnostic.Message {
    return Diagnostic.Message(.error,
      "name '\(local)' shadows shadow qualified '\(n)'")
  }

  static func duplicateImport(_ qn: QualifiedName) -> Diagnostic.Message {
    return Diagnostic.Message(.warning, "duplicate import of \(qn)")
  }

  static func bodyBeforeSignature(_ n: Name) -> Diagnostic.Message {
    return Diagnostic.Message(.error,
      "function body for '\(n)' must appear after function type signature")
  }

  static func recordMissingConstructor(
    _ n: FullyQualifiedName) -> Diagnostic.Message {
    return Diagnostic.Message(.error,
                              "record '\(n)' must have constructor declared")
  }
}
