/// OptimizerPass.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography

/// The parent protocol of all optimizer passes.
///
/// An optimizer pass is a transformation that is run across some or all of
/// the code in a module.  This transformation must be *semantics-preserving*
/// in the sense that it cannot introduce undefined behavior where there was
/// none previously, it may not create ill-typed GIR, and it must not change
/// the observable effects of a program.
///
/// For example, an illegal program transformation would be the removal of a
/// `force_effects` instruction that has users, as this causes sequencing
/// violations during scheduling.
///
/// An optimizer pass must also be a pure function of its inputs.  That
/// is, all local state should be reset for each run.  This is because the
/// `PassPipeliner` will not necessarily create exactly one instance of a pass
/// per registered pass type.  If a local pass needs extra state to perform its
/// job, it should be upgraded to a module pass.
///
/// GraphIR affords passes a lot more freedom and simplicity around
/// optimization than traditional SSA-form IRs.  The Sea of Nodes is amenable to
/// complex transformations by the manipulation of operands alone instead of
/// requiring the shifting of entire regions of instructions.  In addition,
/// deleting instructions is no longer strictly required as long as all their
/// users are removed, as the scheduler takes care of dead value elimination
/// by construction.
///
/// Using This Protocol
/// ===================
///
/// Optimizer passes must not conform to `OptimizerPass` directly.  Instead,
/// one of its specializations must be used.
///
/// - `ScopePass` for passses that implement scope-local transformations.
/// - `ModulePass` for passes that implement module-wide transformations.
///
/// Use With silt-optimize
/// ======================
///
/// The Silt Compiler provides a utility called "silt-optimize" that is capable
/// of running a set of user-provided passes.  These passes are identified by
/// their class name.  Thus if you provide the following declarations
///
///     final class SimplifyCFG: ScopePass { /**/ }
///     final class LoopInvariantCodeMotion: ScopePass { /**/ }
///
/// The corresponding invocation of silt-optimize looks like
///
///     $ silt optimize --pass SimplifyCFG --pass LoopInvariantCodeMotion <File>
public protocol OptimizerPass: class {
  /// Create and return a value of this type.
  init()
}

/// An optimizer pass that is run on every scope in a module.
public protocol ScopePass: OptimizerPass {
  /// Execute the pass on the given scope.
  func run(on scope: Scope)
}

/// An optimizer pass that is run on the entire module.
public protocol ModulePass: OptimizerPass {
  /// Execute the pass on the given module.
  func run(on module: GIRModule)
}
