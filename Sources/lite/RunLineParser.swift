//
//  RunLineParser.swift
//  lite
//
//  Created by Harlan Haskins on 11/20/17.
//

import Lithosphere
import Foundation

struct RunLine {
  enum Command {
    /// Runs silt with the provided arguments
    case run

    /// Runs silt with the provided arguments and consider a non-zero exit code
    /// as a success.
    case runNot
  }
  let command: Command
  let arguments: [String]

  /// Re-serializes the run command as a string
  var asString: String {
    var pieces = [String]()
    switch command {
    case .run: pieces.append("RUN:")
    case .runNot: pieces.append("RUN-NOT:")
    }
    pieces += arguments
    return pieces.joined(separator: " ")
  }

  func isFailure(_ status: Int32) -> Bool {
    switch command {
    case .run: return status == 0
    case .runNot: return status != 0
    }
  }
}

enum RunLineParser {
  // swiftlint:disable force_try
  static let regex = try! NSRegularExpression(pattern: "--\\s*([\\w-]+):(.*)$",
                                              options: [.anchorsMatchLines])
  static func parseRunLines(in file: URL) throws -> [RunLine] {
    var lines = [RunLine]()
    let contents = try String(contentsOf: file, encoding: .utf8)
    let nsString = NSString(string: contents)
    let range = NSRange(location: 0, length: nsString.length)
    for match in regex.matches(in: contents, range: range) {
      let command = nsString.substring(with: match.range(at: 1))
      let runLine = nsString.substring(with: match.range(at: 2))
      let components = runLine.split(separator: " ")
      if components.isEmpty { continue }
      let args = components.map(String.init)
      let cmd: RunLine.Command
      switch command {
      case "RUN": cmd = .run
      case "RUN-NOT": cmd = .runNot
      default: continue
      }
      lines.append(RunLine(command: cmd, arguments: args))
    }
    return lines
  }
}
