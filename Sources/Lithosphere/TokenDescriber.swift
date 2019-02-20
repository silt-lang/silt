/// TokenDescriber.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// A namespace for a function that will print the description of the tokens in
/// a silt file.
public enum TokenDescriber {
  /// Prints a description of each token in the token stream and
  public static
  func describe<Target: TextOutputStream>(_ tokens: [TokenSyntax],
                                          to stream: inout Target,
                                          converter: SourceLocationConverter) {
    for token in tokens {
      stream.write("Token: \(token.tokenKind)")
      let loc = token.sourceRange(converter: converter).start
      let baseName = URL(fileURLWithPath: loc.file).lastPathComponent
      stream.write(" <\(baseName):\(loc.line):\(loc.column)>")

      stream.write("\n")
      stream.write("  Leading Trivia:\n")
      for piece in token.leadingTrivia.pieces {
        stream.write("    \(piece)\n")
      }
      stream.write("  Trailing Trivia:\n")
      for piece in token.trailingTrivia.pieces {
        stream.write("    \(piece)\n")
      }
    }
  }
}
