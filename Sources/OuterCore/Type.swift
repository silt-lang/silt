/// Type.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Moho
import Mantle

public indirect enum Type {
  case metadata(TypeMetadata)
  case value
  case record(DeclaredRecord)
  case function([Type], Type)
}
