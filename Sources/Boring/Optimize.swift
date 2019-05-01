/// Optimize.swift
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
import OuterCore

public final class OptimizeToolOptions: SiltToolOptions {
  public var passes: [String] = []
  public var inputURLs: [Foundation.URL] = []
}


public class SiltOptimizeTool: SiltTool<OptimizeToolOptions> {
  public convenience init(_ args: [String]) {
    self.init(
      toolName: "optimize",
      usage: "[options]",
      overview: "Run optimization pipelines on Silt source code",
      args: args
    )
  }

  private func translateOptions() -> Options {
    return Options(mode: .dump(.girGen),
                   colorsEnabled: false,
                   shouldPrintTiming: false,
                   inputURLs: self.options.inputURLs,
                   target: nil,
                   typeCheckerDebugOptions: [])
  }

  override func runImpl() throws {
    let invocation = Invocation(options: translateOptions())
    let hadErrors = invocation.runToGIRGen { mod in
      let pipeliner = PassPipeliner(module: mod)
      pipeliner.addStage("User-Selected Passes") { p in
        for name in self.options.passes {
          guard let cls = NSClassFromString("OuterCore.\(name)") else {
            print("Could not find pass named '\(name)'")
            continue
          }

          guard let pass = cls as? OptimizerPass.Type else {
            print("Could not find pass named '\(name)'")
            continue
          }
          p.add(pass)
        }
      }
      pipeliner.execute()
    }
    if hadErrors {
      self.executionStatus = .failure
    } else {
      self.executionStatus = .success
    }
  }

  override class func defineArguments(
    parser: ArgumentParser,
    binder: ArgumentBinder<OptimizeToolOptions>
  ) {
    binder.bindArray(
      option: parser.add(option: "--pass", kind: [String].self),
      to: { opt, passes in
        return opt.passes.append(contentsOf: passes)
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
