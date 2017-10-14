/// Node.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
struct Node {
  let typeName: String
  let kind: String
  let collectionElement: String?
  let children: [Child]

  init(_ name: String, kind: String, element: String? = nil,
       children: [Child] = []) {
    self.typeName = name
    self.kind = kind == "Syntax" ? "" : kind
    self.collectionElement = element
    self.children = children
  }
}
