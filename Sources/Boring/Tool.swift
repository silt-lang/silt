/// Tool.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import SPMLibc
import Basic
import SPMUtility
import POSIX

public class SiltToolOptions {
  let verbosity: Int = Verbosity.concise.rawValue
  public required init() {}
}

public class SiltTool<Options: SiltToolOptions> {
  /// The options of this tool.
  let options: Options

  /// Reference to the argument parser.
  let parser: ArgumentParser

  /// The process set to hold the launched processes. These will be terminated
  /// on any signal received by the swift tools.
  let processSet: ProcessSet

  /// The interrupt handler.
  let interruptHandler: InterruptHandler

  /// The execution status of the tool.
  var executionStatus: ExecutionStatus = .success

  /// The stream to print standard output on.
  fileprivate var stdoutStream: OutputByteStream = Basic.stdoutStream

  /// If true, Redirects the stdout stream to stderr when invoking
  /// `swift-build-tool`.
  private var shouldRedirectStdoutToStderr = false

  /// Create an instance of this tool.
  ///
  /// - parameter args: The command line arguments to be passed to this tool.
  public init(toolName: String, usage: String, overview: String, args: [String],
              seeAlso: String? = nil) {
    // Create the parser.
    self.parser = ArgumentParser(
      commandName: "silt \(toolName)",
      usage: usage,
      overview: overview,
      seeAlso: seeAlso)

    // Create the binder.
    let binder = ArgumentBinder<Options>()

    // Let subclasses bind arguments.
    type(of: self).defineArguments(parser: parser, binder: binder)

    do {
      // Parse the result.
      let result = try parser.parse(args)

      var options = Options()
      try binder.fill(parseResult: result, into: &options)

      self.options = options

      let processSet = ProcessSet()
      interruptHandler = try InterruptHandler {
        // Terminate all processes on receiving an interrupt signal.
        processSet.terminate()

        // Install the default signal handler.
        var action = sigaction()
        #if os(macOS)
        action.__sigaction_u.__sa_handler = SIG_DFL
        #else
        action.__sigaction_handler = unsafeBitCast(
          SIG_DFL,
          to: sigaction.__Unnamed_union___sigaction_handler.self)
        #endif
        sigaction(SIGINT, &action, nil)

        // Die with sigint.
        kill(getpid(), SIGINT)
      }
      self.processSet = processSet
    } catch let error {
      if let error = error as? ArgumentParserError {
        SiltTool.exit(with: type(of: self).handleArgumentParserError(error))
      }
      SiltTool.exit(with: .failure)
    }
  }

  class func defineArguments(parser: ArgumentParser,
                             binder: ArgumentBinder<Options>) {
    fatalError("Must be implemented by subclasses")
  }

  class func handleArgumentParserError(
    _ error: ArgumentParserError
  ) -> ExecutionStatus {
    return .failure
  }

  /// Execute the tool.
  public func run() {
    do {
      // Setup the globals.
      verbosity = Verbosity(rawValue: options.verbosity)
      Process.verbose = verbosity != .concise
      // Call the implementation.
      try runImpl()
    } catch {
      // Set execution status to failure in case of errors.
      executionStatus = .failure
    }
    SiltTool.exit(with: executionStatus)
  }

  /// Exit the tool with the given execution status.
  private static func exit(with status: ExecutionStatus) -> Never {
    switch status {
    case .success:
      POSIX.exit(0)
    case .failure:
      POSIX.exit(1)
    }
  }

  /// Run method implementation to be overridden by subclasses.
  func runImpl() throws {
    fatalError("Must be implemented by subclasses")
  }

  /// Start redirecting the standard output stream to the standard error stream.
  func redirectStdoutToStderr() {
    self.shouldRedirectStdoutToStderr = true
    self.stdoutStream = Basic.stderrStream
  }

  /// An enum indicating the execution status of run commands.
  enum ExecutionStatus {
    case success
    case failure
  }
}
