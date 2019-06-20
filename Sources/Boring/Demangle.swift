/// Demangle.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Basic
import SPMUtility
import Drill
import Seismography

public final class DemangleToolOptions: SiltToolOptions {
  var inputNames = [String]()
}

public class SiltDemangleTool: SiltTool<DemangleToolOptions> {
  public convenience init(_ args: [String]) {
    self.init(
      toolName: "demangle",
      usage: "[options]",
      overview: "Demangle silt symbols",
      args: args
    )
  }

  override class func defineArguments(
    parser: ArgumentParser,
    binder: ArgumentBinder<DemangleToolOptions>
  ) {
    binder.bindArray(
      positional: parser.add(
        positional: "",
        kind: [String].self,
        usage: "One or more input strings",
        completion: nil),
      to: { opt, names in opt.inputNames = names })
  }

  override func runImpl() throws {
    precondition(!self.options.inputNames.isEmpty)
    for name in self.options.inputNames {
      SiltDemangleTool.demangle(stdoutStream, name)
      stdoutStream.write("\n")
    }
    stdoutStream.flush()
  }

  override class func handleArgumentParserError(
    _ error: ArgumentParserError
  ) -> ExecutionStatus {
    switch error {
    case .expectedArguments(_, _):
      runDemangleStandardInput()
      return .success
    case .unknownOption("-"):
      runDemangleStandardInput()
      return .success
    default:
      return .failure
    }
  }

  private static func demangle(_ stream: OutputByteStream, _ str: String) {
    guard let pointer = Demangler.demangleSymbol(str) else {
      stream.write(str)
      return
    }
    pointer.print(to: stream)
  }

  private static func runDemangleStandardInput() {
    // swiftlint:disable force_try
    let regex = try! NSRegularExpression(pattern: "\(MANGLING_PREFIX)\\S+")

    while let inputContents = readLine(strippingNewline: true) {
      let full = NSRange(location: 0, length: inputContents.count)
      let matchInfo = regex.matches(in: inputContents, range: full)
      var lastIndex = inputContents.startIndex
      for match in matchInfo {
        for i in 0..<match.numberOfRanges {
          let r = match.range(at: i)
          let matchStart = inputContents.index(inputContents.startIndex,
                                               offsetBy: r.location)
          let matchEnd = inputContents.index(inputContents.startIndex,
                                             offsetBy: NSMaxRange(r))

          // Print the text before the match
          stdoutStream.write(String(inputContents[lastIndex..<matchStart]))

          // Demangle and print the match
          let substr = String(inputContents[
            Range<String.Index>(uncheckedBounds: (matchStart, matchEnd))
          ])
          demangle(stdoutStream, substr)

          // Jump to the end of the match
          lastIndex = matchEnd
        }
      }

      // Print any remaining text
      if lastIndex != inputContents.endIndex {
        stdoutStream.write(String(inputContents[lastIndex..<inputContents.endIndex]))
      }
      stdoutStream.write("\n")
      stdoutStream.flush()
    }
  }
}
