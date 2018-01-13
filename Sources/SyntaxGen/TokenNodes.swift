/// TokenNodes.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

let tokenNodes = [
  Token(name: "Equals", .punctuation("=")),
  Token(name: "LeftParen", .punctuation("(")),
  Token(name: "RightParen", .punctuation(")")),

  // Need to double-escape the forward slash so it shows up
  // single-escaped in the resulting Swift file.
  Token(name: "ForwardSlash", .punctuation("\\\\")),

  Token(name: "LeftBrace", .punctuation("{")),
  Token(name: "RightBrace", .punctuation("}")),
  Token(name: "Semicolon", .punctuation(";")),
  Token(name: "Colon", .punctuation(":")),
  Token(name: "Period", .punctuation(".")),
  Token(name: "Pipe", .punctuation("|")),
  Token(name: "Underscore", .punctuation("_")),

  // Interchangeable with the "forall" keyword.
  Token(name: "ForallSymbol", .punctuation("∀")),

  // Interchangeable with the "->" punctuation.
  Token(name: "ArrowSymbol", .punctuation("→")),

  Token(name: "Constructor", .keyword("constructor")),
  Token(name: "Module", .keyword("module")),
  Token(name: "Open", .keyword("open")),
  Token(name: "Import", .keyword("import")),
  Token(name: "Where", .keyword("where")),
  Token(name: "With", .keyword("with")),
  Token(name: "Let", .keyword("let")),
  Token(name: "In", .keyword("in")),
  Token(name: "Type", .keyword("Type")),
  Token(name: "Data", .keyword("data")),
  Token(name: "Record", .keyword("record")),
  Token(name: "Field", .keyword("field")),
  Token(name: "Forall", .keyword("forall")),
  Token(name: "Infixl", .keyword("infixl")),
  Token(name: "Infixr", .keyword("infixr")),
  Token(name: "Infix", .keyword("infix")),

  Token(name: "Identifier", .associated("String")),
  Token(name: "Unknown", .associated("Character"))
]
