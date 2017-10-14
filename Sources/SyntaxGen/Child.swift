/// Child.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
struct Child {
  let name: String
  let kind: String
  let isOptional: Bool

  init(_ name: String, kind: String, isOptional: Bool = false) {
    self.kind = kind
    self.name = name
    self.isOptional = isOptional
  }
}
