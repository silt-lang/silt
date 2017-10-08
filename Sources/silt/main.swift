import UpperCrust
import Foundation

extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    write(string.data(using: .utf8)!)
  }
}

let fullFile = """
{-
nested {- block comment -}
-}    {- Second block comment -}
\t
-- If foo is true...
if foo
-- The result is \\x -> 3
then \\x -> 4
{- otherwise the result is -- 3 -}
else 3
"""

func describe(_ input: String) {
  let lexer = Lexer(input: input, filePath: "input.silt")
  print("Original Source Text:\n```haskell")
  print(input)
  print("```")

  let tokens = lexer.tokenize()

  for token in tokens {
    print("Token:")
    print("`\(token.tokenKind)", terminator: "")
    if let loc = token.sourceRange?.start {
      print(" <\(loc.file):\(loc.line):\(loc.column)>", terminator: "")
    }
    print("`")
    print("\nLeading Trivia:\n```")
    for piece in token.leadingTrivia.pieces {
      print("\(piece)")
    }
    print("```\nTrailing Trivia:\n```")
    for piece in token.trailingTrivia.pieces {
      print("\(piece)")
    }
    print("```")
  }

  assert(tokens.map { $0.sourceText }.joined() == input)

//  do {
//    var stdout = FileHandle.standardOutput
//    let parser = Parser(tokens: tokens)
//    let node = try parser.parseType()
//    let dumper = SyntaxDumper(stream: &stdout)
//    dumper.dump(node)
//    print("Parsed: \(node.sourceText)")
//  } catch {
//    print("error: \(error)")
//  }
}

describe("""
{- A type -}
module Prelude where

id : forall (k : Level) . forall (X : Type k) -> X -> X
id x = x
""")
