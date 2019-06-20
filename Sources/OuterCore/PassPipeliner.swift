/// PassPipeliner.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography

/// Implements a pass manager, pipeliner, and executor for a set of
/// user-provided optimization passes.
///
/// A `PassPipeliner` handles the creation of a related set of optimization
/// passes called a "pipeline".  Grouping passes is done for multiple reasons,
/// chief among them is that optimizer passes are extremely sensitive to their
/// ordering relative to other passses.  In addition, pass groupings allow for
/// the clean segregation of otherwise unrelated passes.  For example, a
/// pipeline might consist of "mandatory" passes such as Jump Threading, LICM,
/// and DCE in one pipeline and "diagnostic" passes in another.
public final class PassPipeliner {
  /// The module for this pass pipeline.
  public let module: GIRModule
  public private(set) var stages: [String]
  public private(set) var passes: [String: [OptimizerPass.Type]]
  private var frozen: Bool = false

  public final class Builder {
    fileprivate var passes: [OptimizerPass.Type] = []

    fileprivate init() {}

    /// Appends a pass to the current pipeline.
    public func add(_ type: OptimizerPass.Type) {
      self.passes.append(type)
    }
  }

  /// Initializes a new, empty pipeliner.
  ///
  /// - Parameter module: The module the pipeliner will run over.
  public init(module: GIRModule) {
    self.module = module
    self.stages = []
    self.passes = [:]
  }

  /// Appends a stage to the pipeliner.
  ///
  /// The staging function provides a `Builder` object into which the types
  /// of passes for a given pipeline are inserted.
  ///
  /// - Parameters:
  ///   - name: The name of the pipeline stage.
  ///   - stager: A builder function.
  public func addStage(_ name: String, _ stager: (Builder) -> Void) {
    precondition(!self.frozen, "Cannot add new stages to a frozen pipeline!")

    self.frozen = true
    defer { self.frozen = false }

    self.stages.append(name)
    let builder = Builder()
    stager(builder)
    self.passes[name] = builder.passes
  }

  /// Executes the entirety of the pass pipeline.
  ///
  /// Execution of passes is done in a loop that is divided into two phases.
  /// The first phase aggregates all local passes and stops aggregation when
  /// it encounters a module-level pass.  This group of local passes
  /// is then run one at a time on the same scope.  The second phase is entered
  /// and the module pass is run.  The first phase is then re-entered until all
  /// local passes have run on all local scopes and all intervening module
  /// passes have been run.
  ///
  /// The same pipeline may be repeatedly re-executed, but pipeline execution
  /// is not re-entrancy safe.
  public func execute() {
    precondition(!self.frozen, "Cannot execute a frozen pipeline!")

    self.frozen = true
    defer { self.frozen = false }

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
