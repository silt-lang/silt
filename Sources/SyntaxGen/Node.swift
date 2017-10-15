/// Node.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
struct Node {
  enum Kind {
    case collection(element: String)
    case node(kind: String, children: [Child])
  }
  let typeName: String
  let kind: Kind

  init(_ typeName: String, element: String) {
    self.typeName = typeName
    self.kind = .collection(element: element)
  }

  init(_ typeName: String, kind: String, children: [Child]) {
    self.typeName = typeName
    self.kind = .node(kind: kind == "Syntax" ? "" : kind,
                      children: children)
  }
}
