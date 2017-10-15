/// Token.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

struct Token {
  enum Kind {
    case associated(String)
    case keyword(String)
    case punctuation(String)
  }
  let caseName: String
  let name: String
  let kind: Kind

  init(name: String, _ kind: Kind) {
    self.kind = kind
    self.name = name
    var caseName = name.replacingOccurrences(of: "Token", with: "")
      .lowercaseFirstLetter
    if case .keyword(_) = kind {
      caseName += "Keyword"
    }
    self.caseName = caseName
  }
}
