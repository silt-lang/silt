import Foundation
import Basic
import Utility
import Drill
import FileCheck
import Lithosphere
import Rainbow

func run() -> Int {
  let cli = ArgumentParser(usage: "FileCheck", overview: "")
  let binder = ArgumentBinder<FileCheckOptions>()
  //swiftlint:disable statement_position
  binder.bind(option:
    cli.add(option: "-disable-colors", kind: Bool.self,
            usage: "Disable colorized diagnostics"),
              to: { if $1 { $0.insert(.disableColors) }
                    else { $0.remove(.disableColors) } })
  binder.bind(option:
    cli.add(option: "-use-strict-whitespace",
            kind: Bool.self,
            usage: "Do not treat all horizontal whitespace as equivalent"),
              to: { if $1 { $0.insert(.strictWhitespace) }
                    else { $0.remove(.strictWhitespace) } })
  binder.bind(option:
    cli.add(option: "-allow-empty-input", shortName: "-e",
            kind: Bool.self,
            usage: """
                   Allow the input file to be empty. This is useful when \
                   making checks that some error message does not occur, \
                   for example.
                   """),
              to: { if $1 { $0.insert(.allowEmptyInput) }
                    else { $0.remove(.allowEmptyInput) } })
  binder.bind(option:
    cli.add(option: "-match-full-lines",
            kind: Bool.self,
            usage: """
                   Require all positive matches to cover an entire input line. \
                   Allows leading and trailing whitespace if \
                   -strict-whitespace is not also used.
                   """),
              to: { if $1 { $0.insert(.matchFullLines) }
                    else { $0.remove(.matchFullLines) } })
  let prefixes =
    cli.add(option: "-prefixes", kind: [String].self,
            usage: """
                   Specifies one or more prefixes to match. By default these \
                   patterns are prefixed with “CHECK”.
                   """)

  let inputFile =
    cli.add(option: "-input-file", shortName: "-i",
            kind: String.self,
            usage: "The file to use for checked input. Defaults to stdin.")

  let file =
    cli.add(positional: "", kind: String.self,
            usage: "")

  let args = Array(CommandLine.arguments.dropFirst())
  guard let results = try? cli.parse(args) else {
    cli.printUsage(on: stderrStream)
    return -1
  }

  let engine = DiagnosticEngine()
  engine.register(PrintingDiagnosticConsumer(stream: &stderrStream))

  guard let filePath = results.get(file) else {
    engine.diagnose(.requiresOneCheckFile)
    return -1
  }

  var options = FileCheckOptions()
  binder.fill(results, into: &options)
  Rainbow.enabled = !options.contains(.disableColors)

  let fileHandle: FileHandle
  if let input = results.get(inputFile) {
    guard let handle = FileHandle(forReadingAtPath: input) else {
      engine.diagnose(.couldNotOpenFile(input))
      return -1
    }
    fileHandle = handle
  } else {
    fileHandle = .standardInput
  }
  var checkPrefixes = results.get(prefixes) ?? []
  checkPrefixes.append("CHECK")

  let matchedAll = fileCheckOutput(of: .stdout,
                                   withPrefixes: checkPrefixes,
                                   checkNot: [],
                                   against: .filePath(filePath),
                                   options: options) {
    // FIXME: Better way to stream this data?
    FileHandle.standardOutput.write(fileHandle.readDataToEndOfFile())
  }

  return matchedAll ? 0 : -1
}

exit(Int32(run()))
