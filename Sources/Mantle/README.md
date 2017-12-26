The Mantle library contains the source for type checking and elaborating
well-scoped Silt terms.  The Mantle uses [Gundry-McBride Dynamic Pattern
Unification](http://adam.gundry.co.uk/pub/pattern-unify/) to power its analysis.

Notation & Preliminaries
========================

We implement a *bidirectional* typechecking algorithm: An algorithm that is
always either checking terms have a particular type or synthesizing a type for
a given term (under an environment).

We denote *metavariables*, entities created by the type solving process, by `$n`
for `n` a non-negative integer.

A declaration, variable, or metavariable may be *applied* to some other vector
of terms.  We denote this application (here, of a metavariable `$0`) by `$0[e0,
e1, ..., en]` for `en` a TT term or a record field name. Applied terms in the 
core Type Theory (TT) always appear in *spine form*, which, like the notation, 
means that we keep the variable "head" near the vector "spine" while performing
type analysis.  This is not only convenient, but more efficient because most 
algorithms assume we simplify terms to this representation before executing them.

Variables that appear as the argument of a metavariable are called *flexible*
(as opposed to *rigid*).  e.g. Both `Y` and `Z` in `$0[X] -> Y[Z]` are *rigid*
while `X` is *flexible*.

A *telescope* (sometimes, though not here, denoted `Φ = [(x1 : T1), (x2 : T2),
... (xn : Tn)]`) is a vector of name bindings with corresponding types.
Telescopes differ from contexts in non-dependent settings as later types `Ti`
may depend on earlier terms `x1, ..., x(i-1)`.

The function space of such dependent terms is denoted `Π (x : S) -> T(x)`
(similarly, for a telescope of leading terms, `Π Φ -> T`).

Silt's Type Theory implements a homogeneous *intensional equality* of terms up
to *reductions* given by the following conversions:

    - Alpha Conversion: (Capture-avoiding) renaming of variables in terms.
      `λx . α x x ≡ λy. α y y`.
    - Beta Conversion: (Familiar) computation of applications of terms to binders
      `(λx y . x + y) 4 5 ≡ 9`
    - Delta Conversion: Expansion of definienda to their definitions.
    - Eta Conversion: The addition (Eta Expansion) or subtraction (Eta
      Contraction) of an abstraction
      `λx . α x ≡ α`

Type Analysis
=============

The Mantle divides type analysis into three broad phases:

    - Type Checking
    - Elaboration
    - Type Solving

All of these phases are manifest in the `TypeChecker<T>` type which is
parametrized by phase-specific state.

Type Checking
=============

Type checking concerns checking the consistency of the types and terms involved
in expressions and datatypes.  It provides the initial entrypoint into the rest
of the Mantle and directs the overall type analysis phase.  Types for terms are 
initially synthesized and solved by the Elaboration phase, at which point the 
type checker proper takes over and verifies that the synthesized types are correct.

Elaboration
===========

Elaboration is the process of converting userland AST that has been checked for
scope consistency into an AST that is amenable to type analysis.  We call this
type analysis AST `TT`, after the core type theory.  In order to verify the
correctness of generated terms, elaboration generates heterogeneous constraints
between a given term and an expected type.  

Because elaboration is a mechanical process, it does not concern itself with
whether terms are type-correct.  It can only detect serious structural problems
which should have been caught by earlier phases.  Elaboration should preserve as
much user-provided structure as possible to enable better diagnostics.

Type Solving
============

Heterogeneous constraints from the elaborator are submitted to the type solver.
There are several algorithms for higher-order unification, each with its own
respective strengths and weaknesses.  We implement Gundry-McBride Dynamic
Pattern Unification because the typing problems it solves have a number of
desirable properties.

Miller identified a subset of unification problems called the *pattern
fragment*.  Terms in the pattern fragment involve metavariables applied to
*distinct* variables e.g. `α x y ≡ β x`.  Problems in the pattern fragment are
not only decidable, but yield most general unifiers.  This was later extended by
Pfenning to dependent type systems.  Abel and Pientka presented an extension to
Miller and Pfenning's work that could handle records (Σ types).  Gundry and
McBride later refined this and presented a tutorial implementation in Haskell.

### Dynamism

Because the pattern fragment is just that, a fragment, not all constraints
involve terms that reside in that fragment.  Hence, the solver implements
constraint postponement in the hope that solving further equations will yield
solutions to a currently-stuck constraint.  We take a page from Pientka and Abel
and implement the following solver steps:

1. Eta Expansion & Contraction
    - To solve problems of the form `(s : Π S1 -> S2) ≡ (t : Π T1 -> T2)`, we can
      η-expand the constraint into `∀ x . s x : S2 x ≡ t x : T2 x`.
2. Rigid-rigid Decomposition
    - For two spine-form terms, we may unify them by matching their heads and 
      their spines.
3. Inversion
    - Also called *flex-rigid* problems because one term is a spine-form with
      a metavariable head and the other is not.
    - If we may solve for the head, and the result is in the patten fragment, we
      can generate a substitution and apply it immediate to solve the
      constraint.
4. Intersection
    - Also called *flex-flex* problems because both terms are spine-forms with
      the same metavariable head.
    - For `$0[x1, ..., xn] ≡ $1[y1, ..., yn]`, any position where the arguments
      to the metavariable differ indicates that the arugments are *independent*
      of the head metavariable.  We can thus remove them to simplify the
      constraint.
5. Pruning
    - Pruning occurs after inversion or intersection.
    - When solving `∀Γ . $0[e1, ..., en] ≡ t`, we ensure that only those
      variables `e1, ..., en` appear in `t`.  If `t` contains any other
      variables, they may be removed.
    - If any variables not in `e1, ..., en` occur as arguments to a metavariable
      inside of `t`, we may fail immediately because there is no solution to
      that constraint.

Solving Constraints
===================

Constraints in the solver are of the form `∀Γ . t1 ≡_T t2`.  This reads as
"under the context (telescope) `Γ`, terms `t1` and `t2` share type `T` and
further unify (up to the conversions defined above). 

Constraints are solved in three phases: An early-exit syntactic equality check,
preliminary eta expansion, and reduction followed by metavariable binding.  When
the algorithm detects that terms and types in constraints reside in the pattern
fragment, it eagerly solves for any metavariables it can and moves on.  Else, it
breaks down into simpler constraints and fills the constraint with metavariables 
that are blocking the solver.  As constraint solving proceeds, this blocking set
may cause a constraint to become active again, so we check it before solving
a constraint, postponing if no further binding has been made.

It is possible for constraint solving to terminate without binding all generated
metavariables.  In that case, the generated solution is *malformed* and should
be examined by a diagnostics phase.


