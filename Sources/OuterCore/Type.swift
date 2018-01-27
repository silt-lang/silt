/// Type.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Mantle

enum Type {
  case metadata(TT)
  case value
  case record(DeclaredRecord)
  case type(TT)
}
