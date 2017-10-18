/// TokenDescriber.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// A namespace for a function that will print the description of the tokens in
/// a silt file.
public enum TokenDescriber {
  /// Prints a description of each token in the token stream and
  public static func describe(_ tokens: [TokenSyntax]) {
    for token in tokens {
      print("Token:", "\(token.tokenKind)", terminator: "")
      if let loc = token.sourceRange?.start {
        let baseName = URL(fileURLWithPath: loc.file).lastPathComponent
        print(" <\(baseName):\(loc.line):\(loc.column)>")
      }
      print("  Leading Trivia:")
      for piece in token.leadingTrivia.pieces {
        print("    \(piece)")
      }
      print("  Trailing Trivia:")
      for piece in token.trailingTrivia.pieces {
        print("    \(piece)")
      }
    }
  }
}
