/// ScopeDiagnostics.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere

extension Diagnostic.Message {
  static func ambiguousName(
    _ n: Name, _ others: [FullyQualifiedName]) -> Diagnostic.Message {
    return Diagnostic.Message(.error, "\(n) could be any of \(others)")
  }

  static func nameReserved(_ n: Name) -> Diagnostic.Message {
    return Diagnostic.Message(.error, "cannot use reserved name \(n)")
  }

  static func nameShadows(_ n: Name) -> Diagnostic.Message {
    return Diagnostic.Message(.error, "cannot shadow name \(n)")
  }

  static func nameShadows(
    _ n: Name, local: FullyQualifiedName) -> Diagnostic.Message {
    return Diagnostic.Message(.error,
                              "cannot shadow qualified name \(local) with \(n)")
  }

  static func duplicateImport(_ qn: QualifiedName) -> Diagnostic.Message {
    return Diagnostic.Message(.warning, "\(qn) already imported")
  }
}
