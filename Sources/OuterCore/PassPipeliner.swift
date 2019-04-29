/// PassPipeliner.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography

public final class PassPipeliner {
  public let module: GIRModule
  public private(set) var stages: [String]
  public private(set) var passes: [String: [OptimizerPass.Type]]
  

  public final class Builder {
    fileprivate var passes: [OptimizerPass.Type] = []

    fileprivate init() {}

    public func add(_ type: OptimizerPass.Type) {
      self.passes.append(type)
    }
  }

  public init(module: GIRModule) {
    self.module = module
    self.stages = []
    self.passes = [:]
  }

  public func addStage(_ name: String, _ f: (Builder) -> Void) {
    self.stages.append(name)
    let builder = Builder()
    f(builder)
    self.passes[name] = builder.passes
  }

  public func execute() {
    for stage in self.stages {
      let passTypes = self.passes[stage, default: []]
      guard !passTypes.isEmpty else {
        continue
      }

      var scopePasses = [ScopePass]()
      for type in self.passes[stage, default: []] {
        let pass = type.init()
        if let contPass = pass as? ScopePass {
          scopePasses.append(contPass)
        } else if let modPass = pass as? ModulePass {
          self.runScopePasses(scopePasses)
          scopePasses.removeAll()

          modPass.run(on: self.module)
        } else {
          fatalError("Pass must be Function or Module pass")
        }
      }
      self.runScopePasses(scopePasses)
      scopePasses.removeAll()
    }
  }

  private func runScopePasses(_ passes: [ScopePass]) {
    struct WorklistEntry {
      let scope: Scope
      var index: Int
    }

    var worklist = [WorklistEntry]()
    worklist.reserveCapacity(self.module.continuations.count)
    for scope in self.module.topLevelScopes {
      worklist.append(WorklistEntry(scope: scope, index: 0))
    }

    while !worklist.isEmpty {
      let tailIdx = worklist.count - 1
      let pipelineIdx = worklist[tailIdx].index
      let scope = worklist[tailIdx].scope

      if worklist[tailIdx].index >= passes.count {
        // All passes did already run for the function. Pop it off the worklist.
        _ = worklist.popLast()
        continue
      }

      passes[pipelineIdx].run(on: scope)
      worklist[tailIdx].index += 1
    }
  }
}
