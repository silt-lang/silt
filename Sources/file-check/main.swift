import Foundation
import CommandLine
import FileCheck
import Drill
import Lithosphere
import Rainbow

func run() -> Int {
  let cli = CLI()
  let disableColors =
    BoolOption(longFlag: "disable-colors",
               helpMessage: "Disable colorized diagnostics.")
  let strictWhitespace =
    BoolOption(longFlag: "use-strict-whitespace",
      helpMessage: "Do not treat all horizontal whitespace as equivalent.")

  let allowEmptyInput =
    BoolOption(shortFlag: "e", longFlag: "allow-empty-input",
      helpMessage: """
                   Allow the input file to be empty. This is useful when \
                   making checks that some error message does not occur, \
                   for example.
                   """)
  let matchFullLines =
    BoolOption(longFlag: "match-full-lines",
      helpMessage: """
                   Require all positive matches to cover an entire input line. \
                   Allows leading and trailing whitespace if \
                   --strict-whitespace is not also used.
                   """)
  let prefixes =
    MultiStringOption(longFlag: "prefixes",
      required: false,
      helpMessage: """
                   Specifies one or more prefixes to match. By default these \
                   patterns are prefixed with “CHECK”.
                   """)
  let inputFile =
    StringOption(shortFlag: "i", longFlag: "input-file",
      required: false,
      helpMessage: "The file to use for checked input. Defaults to stdin.")
  cli.addOptions(disableColors, strictWhitespace, allowEmptyInput,
                 matchFullLines, prefixes, inputFile)

  do {
    try cli.parse()
  } catch {
    cli.printUsage()
    return -1
  }

  let engine = DiagnosticEngine()
  engine.register(PrintingDiagnosticConsumer(stream: &stderrStream))

  guard cli.unparsedArguments.count == 1 else {
    engine.diagnose(.requiresOneCheckFile)
    return -1
  }

  var options = FileCheckOptions()
  if disableColors.value { options.insert(.disableColors) }
  if strictWhitespace.value { options.insert(.strictWhitespace) }
  if allowEmptyInput.value { options.insert(.allowEmptyInput) }
  if matchFullLines.value { options.insert(.matchFullLines) }
  Rainbow.enabled = !disableColors.value

  let fileHandle: FileHandle
  if let input = inputFile.value {
    guard let handle = FileHandle(forReadingAtPath: input) else {
      engine.diagnose(.couldNotOpenFile(input))
      return -1
    }
    fileHandle = handle
  } else {
    fileHandle = .standardInput
  }
  var checkPrefixes = prefixes.value ?? []
  checkPrefixes.append("CHECK")

  let matchedAll = fileCheckOutput(of: .stdout,
                                   withPrefixes: checkPrefixes,
                                   checkNot: [],
                                   against: .filePath(cli.unparsedArguments[0]),
                                   options: options) {
    // FIXME: Better way to stream this data?
    FileHandle.standardOutput.write(fileHandle.readDataToEndOfFile())
  }

  return matchedAll ? 0 : -1
}

exit(Int32(run()))
