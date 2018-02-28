/// SemaDiagnostics.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho

extension Diagnostic.Message {
  static var noAbsurdPatternInRHS: Diagnostic.Message {
    return Diagnostic.Message(.error,
      """
      right-hand side of function clause can only be omitted if there is an \
      absurd pattern
      """)
  }

  static func absurdPatternIsValid(_ tyName: TT) -> Diagnostic.Message {
    return Diagnostic.Message(.error,
      """
      absurd pattern of type '\(tyName)' in clause should not have \
      possible valid patterns
      """)
  }

  static func absurdPatternInstantiatesWith(
    _ pat: Pattern) -> Diagnostic.Message {
    return Diagnostic.Message(.note,
      """
      possible valid pattern: '\(pat)'
      """)
  }
}
