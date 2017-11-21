//
//  RunLineParser.swift
//  lite
//
//  Created by Harlan Haskins on 11/20/17.
//

import Foundation

enum RunLineParser {
  // swiftlint:disable force_try
  static let regex = try! NSRegularExpression(pattern: "RUN:(.*)")
  static func parseRunLines(in file: URL) throws -> [[String]] {
    var lines = [[String]]()
    let contents = try String(contentsOf: file, encoding: .utf8)
    let nsString = NSString(string: contents)
    let range = NSRange(location: 0, length: nsString.length)
    for match in regex.matches(in: contents, range: range) {
      let runLine = nsString.substring(with: match.range(at: 1))
      let components = runLine.split(separator: " ")
      if components.isEmpty { continue }
      lines.append(components.map(String.init))
    }
    return lines
  }
}
