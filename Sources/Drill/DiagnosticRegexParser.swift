/// DiagnosticRegexParser.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// A RegexPiece is either:
///  - A literal string that must be matched exactly.
///  - A regular expression that must be matched using regex matching.
/// To construct a regular expression from these pieces, `literal` pieces
/// must be escaped such that they will always match special regex
/// characters literally.
enum RegexPiece {
  /// The string inside must be matched by the resulting regex literally.
  case literal(String)

  /// The string inside is a regex that must be added wholesale into the
  /// resulting regex.
  case regex(String)

  /// Regex-escapes the piece appropriately, taking into account the need
  /// to escape special characters in literals.
  var asRegex: String {
    switch self {
    case .literal(let str):
      return NSRegularExpression.escapedPattern(for: str)
    case .regex(let str):
      return str
    }
  }
}

/// A regex that matches a sub-regex inside a diagnostic expectation.
/// It will look something like: --expected-error{{foo something {{.*}} bar}}
//swiftlint:disable force_try
private let subRegexRegex = try! NSRegularExpression(pattern:
  "\\{\\{([^\\}]+)\\}\\}")

enum DiagnosticRegexParser {
  /// Parses a diagnostic message as an alternating sequence of regex and non-
  /// regex pieces. This will produce a regular expression that will match
  /// messages and will incorporate the regexes inside the message.
  static func parseMessageAsRegex(
    _ message: String) -> NSRegularExpression? {

    // Get an NSString for the message.
    let nsString = NSString(string: message)
    let range = NSRange(location: 0, length: nsString.length)
    var pieces = [RegexPiece]()

    // The index into the string where the last regex's '}}' ends.
    // 'Starts' at 0, so we pull the beginning of the string before the first
    // '{{' as well.
    var previousMatchEnd = 0

    // Enumerate over all matches in the string...
    for match in subRegexRegex.matches(in: message, range: range) {
      let fullRange = match.range(at: 0)

      // Find the range where the previous matched piece ended -- this contains
      // a literal that we need to add to the set of pieces.
      let previousPieceRange =
        NSRange(location: previousMatchEnd,
                length: fullRange.location - previousMatchEnd)
      previousMatchEnd = fullRange.upperBound
      let previousPiece = nsString.substring(with: previousPieceRange)
      pieces.append(.literal(previousPiece))

      // Now, add the regex that we matched.
      let regexRange = match.range(at: 1)
      let pattern = nsString.substring(with: regexRange)
      pieces.append(.regex(pattern))
    }

    // If we still have input left to consume, add it as a literal to the
    // pieces.
    if previousMatchEnd < nsString.length - 1 {
      pieces.append(.literal(nsString.substring(from: previousMatchEnd)))
    }

    // Escape all the pieces and convert the pattern to an NSRegularExpression.
    let pattern = pieces.map { $0.asRegex }.joined()
    return try? NSRegularExpression(pattern: pattern)
  }
}
