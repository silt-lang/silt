/// Frontend.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Basic
import Utility
import Mantle
import Drill

public final class FrontendToolOptions: SiltToolOptions {
  public var mode: Mode = .compile
  public var colorsEnabled: Bool = false
  public var shouldPrintTiming: Bool = false
  public var inputURLs: [Foundation.URL] = []
  public var typeCheckerDebugOptions: TypeCheckerDebugOptions = []
}

extension Mode.VerifyLayer: StringEnumArgument {
  public static var completion: ShellCompletion {
    return ShellCompletion.values([
      ("parse", "Verify the result of parsing the input file(s)"),
      ("scopes", "Verify the result of scope checking the input file(s)"),
    ])
  }
}

extension Mode.DumpLayer: StringEnumArgument {
  public static var completion: ShellCompletion {
    return ShellCompletion.values([
      (Mode.DumpLayer.tokens.rawValue,
       "Dump the result of tokenizing the input file(s)"),
      (Mode.DumpLayer.parse.rawValue,
       "Dump the result of parsing the input file(s)"),
      (Mode.DumpLayer.file.rawValue,
       "Dump the result of parsing and reconstructing the input file(s)"),
      (Mode.DumpLayer.shined.rawValue,
       "Dump the result of shining the input file(s)"),
      (Mode.DumpLayer.scopes.rawValue,
       "Dump the result of scope checking the input file(s)"),
    ])
  }
}

public class SiltFrontendTool: SiltTool<FrontendToolOptions> {
  public convenience init(args: [String]) {
    self.init(
      toolName: "frontend",
      usage: "[options]",
      overview: "Build sources into binary products",
      args: args
    )
  }

  override func runImpl() throws {
    let invocation = Invocation(options: translateOptions())
    if invocation.run() {
      self.executionStatus = .failure
    } else {
      self.executionStatus = .success
    }
  }

  private func translateOptions() -> Options {
    return Options(
      mode: self.options.mode,
      colorsEnabled: self.options.colorsEnabled,
      shouldPrintTiming: self.options.shouldPrintTiming,
      inputURLs: self.options.inputURLs,
      typeCheckerDebugOptions: self.options.typeCheckerDebugOptions)
  }

  override class func defineArguments(
    parser: ArgumentParser,
    binder: ArgumentBinder<FrontendToolOptions>
  ) {
    binder.bind(
      option: parser.add(
        option: "--dump",
        kind: Mode.DumpLayer.self,
        usage: "Dump the result of compiling up to a given layer"),
      to: { opt, r in opt.mode = .dump(r) })
    binder.bind(
      option: parser.add(
        option: "--verify",
        kind: Mode.VerifyLayer.self,
        usage: "Verify the result of compiling up to a given layer"),
      to: { opt, r in opt.mode = .verify(r) })
    binder.bind(
      option: parser.add(option: "--color-diagnostics", kind: Bool.self),
      to: { opt, r in opt.colorsEnabled = r })
    binder.bind(
      option: parser.add(option: "--debug-print-timing", kind: Bool.self),
      to: { opt, r in opt.shouldPrintTiming = r })
    binder.bind(
      option: parser.add(option: "--debug-constraints", kind: Bool.self),
      to: { opt, r in
        if r {
          opt.typeCheckerDebugOptions.insert(.debugConstraints)
        }
    })
    binder.bind(
      option: parser.add(option: "--debug-metas", kind: Bool.self),
      to: { opt, r in
        if r {
          opt.typeCheckerDebugOptions.insert(.debugMetas)
        }
    })
    binder.bind(
      option: parser.add(option: "--debug-normalized-metas", kind: Bool.self),
      to: { opt, r in
        if r {
          opt.typeCheckerDebugOptions.insert(.debugNormalizedMetas)
        }
    })
    binder.bindArray(
      positional: parser.add(
        positional: "",
        kind: [String].self,
        usage: "One or more input file(s)",
        completion: .filename),
      to: { opt, fs in
        let url = fs.map(URL.init(fileURLWithPath:))
        return opt.inputURLs.append(contentsOf: url)
    })
  }
}
