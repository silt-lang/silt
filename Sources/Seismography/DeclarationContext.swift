/// DeclarationContext.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public enum DeclarationContextKind {
  case module
  case continuation
  case datatype
  case record
}

public protocol DeclarationContext {
  var contextKind: DeclarationContextKind { get }
  var parent: DeclarationContext? { get }
}
