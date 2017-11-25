/// RunLineParser.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Foundation

/// A Run line is a line in a Lite test file that contains a set of command-line
/// arguments to pass to a `silt` program.
struct RunLine {
  /// The command, either `RUN:` or `RUN-NOT:`.
  enum Command {
    /// Runs silt with the provided arguments
    case run

    /// Runs silt with the provided arguments and consider a non-zero exit code
    /// as a success.
    case runNot
  }

  /// The command to execute.
  let command: Command

  /// The arguments to pass to `silt`.
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

  /// Determines if a given process exit code is a failure or success, depending
  /// on the run line's command.
  func isFailure(_ status: Int32) -> Bool {
    switch command {
    case .run: return status == 0
    case .runNot: return status != 0
    }
  }
}

/// Namespace for run line parsing routines.
enum RunLineParser {
  // swiftlint:disable force_try
  static let regex = try! NSRegularExpression(pattern: "--\\s*([\\w-]+):(.*)$",
                                              options: [.anchorsMatchLines])

  /// Parses the set of RUN lines out of the file at the provided URL, and
  /// returns a set of commands that it parsed.
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
