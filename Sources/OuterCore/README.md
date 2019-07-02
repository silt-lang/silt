The Outer Core library implements a middle-end optimizer for GraphIR terms.

Introduction
=========

The goal of any optimizer is to efficiently, expediently, and safely transform a given program into
a more effective program. Luckily, program optimization is a rich and fruitful subfield of 
compiler research, and a wide variety of techniques are available to accomplish this goal.  Further,
because we rely on the expertise and experience of the LLVM project, there is a wide class of
(usually lower-level) optimizations that we need not concern ourselves with.

Because GraphIR is a middle-end IR, we are concerned with simplifying and canonicalizing
programs more than we are with larger, even whole-program, transformations.  Our IR being
in continuation-passing-style also lends itself well to this class of transformations.

Passes
======

A pass is an independent unit of a particular program transformation, analysis,
or report.  A pass can choose to restrict itself to a particular scope - currently the level of
a GraphIR `Scope` or a GraphIR `Module`. Silt provides a pass pipelining infrastructure to
efficiently schedule and run groupings of related passes.

Silt provides the protocol `OptimizerPass` to allow the compiler to abstract over
all kinds of passes.  However, passes should never conform directly to `OptimizerPass`, 
choosing instead to conform to one of its direct descendents:

### ScopePass

`ScopePass` is appropriate for a scope-level transformation.  A scope is the GraphIR equivalent
of a function in a more traditional SSA-form compiler.  It includes an entry continuation, and all
IR-level data dependencies. Thorin calls these dependencies *direct* if a data operand from 
one continuation is used by a primop, or *indirect* if is used as a the callee of an application.  A
scope is the result of applying a simple liveness analysis beginning from a set of entry 
continuations that roughly correspond one-to-one to user functions.  However, because silt and
GraphIR have no concept of dependency on the address of a function, this is simply an
implementation detail.

This definition of GraphIR scope is thus more expansive than the notion of nested scopes in
block-based IRs, as it allows naive traversals to see indirect dependencies in continuations
that would otherwise require module-wide passes to discover.  This makes scope passes great
not just for the usual code motion, dataflow, and loop optimizations, but also for higher level
passes like *(mutual) tail-recursion elimination*, *lambda-lifting/lambda-dropping*, and *inlining*
of both closures and functions that would otherwise be burdensome to implement.

### ModulePass

`ModulePass` is appropriate for a module-wide transformation or analysis pass.  It fits best for
immutable inter-procedural analyses.  For example, LLVM and Swift both provide a 
"merge functions" pass that identifies functions that differ in form but not in semantics and 
merges them into a common function.

silt optimize
=========

To make testing the optimizer and individual optimizer passes easy, silt provides the `optimize`
subtool.  The class names of passes defined in the OuterCore are used to dynamically 
instantiate and run a user-provided set of optimizer passes over a user-provided set of
files (both `.gir` files and `.silt` files).

Thus if you provide the following declarations:

```swift
final class SimplifyCFG: ScopePass { /**/ }
final class LoopInvariantCodeMotion: ScopePass { /**/ }
```

The corresponding invocation of `silt-optimize` looks like

```bash
$ silt optimize --pass SimplifyCFG --pass LoopInvariantCodeMotion <Files>
```
