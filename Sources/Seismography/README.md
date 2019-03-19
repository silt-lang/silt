The Seismography library implements a graph-based intermediate representation
loosely based on [Thorin, by Leißa, et. al.](http://compilers.cs.uni-saarland.de/papers/lkh15_cgo.pdf)

SeismoGraphIR
============

SeismoGraphIR - GraphIR or GIR for short - is a [Continuation Passing Style (or CPS)](https://en.wikipedia.org/wiki/Continuation-passing_style), 
[Sea of Nodes](http://www.oracle.com/technetwork/java/javase/tech/c2-ir95-150110.pdf), 
[SSA-form](https://en.wikipedia.org/wiki/Static_single_assignment_form) IR with a mix of
high and low-level semantic information designed to implement the Silt programming 
language. We designed GraphIR for the following use cases:

- A target-independent high-level overview of the expected runtime behavior of 
Silt programs.
- High-level optimization passes, including defunctionalization, closure inlining, 
memory allocation promotion, and generic function instantiation.
- Function inlining and specialization across modules while still accommodating separate compilation.

Syntax
=====

The syntax of GraphIR is loosely based on [Thorin, by Leißa, et. al.](http://compilers.cs.uni-saarland.de/papers/lkh15_cgo.pdf) and by [SIL](https://github.com/apple/swift/blob/master/docs/SIL.rst). GIR files use the `.gir`  file extension. 

An example GIR file is given below:

```llvm
module Example where

-- data Bool : Type where
--   tt : Bool
--   ff : Bool

-- if_then_else_ : Bool -> Bool -> Bool -> Bool
-- if tt then x else _ = x
-- if ff then _ else x = x

@Example.if_then_else_ : (Example.Bool ; Example.Bool ; Example.Bool) -> (Example.Bool) -> _ {
bb0(%0 : Example.Bool; %1 : Example.Bool; %2 : Example.Bool; %3 : (Example.Bool) -> _):
  %4 = function_ref @bb2
  %5 = function_ref @bb1
  switch_constr %0 : Example.Bool ; Example.Bool.tt : %4 ; Example.Bool.ff : %5
  
bb1:
  apply %3(%2) : (Example.Bool) -> _
  
bb2:
  apply %3(%1) : (Example.Bool) -> _
} -- end gir function Example.if_then_else_
```

Values and Operands
================

```
id ::= <a group of non-space unicode characters>
id-list ::= <id> | <id-list>

qualified-name ::= <id> | <id> '.' <qualified-name>

gir-value-id ::= '%' <id>
gir-value-id-list ::= <gir-value-id> | <gir-value-id-list>

operand ::= <gir-value-id> ':' <gir-type>

ownership-qualifier ::= 'take' | 'copy'
```

GIR values are introduced by the `%` sigil and a unique alphanumeric identifier.

Functions
=======

```
decl ::= <function-decl>
function-decl ::= '@' <qualified-name> ':' <gir-type> '{' <continuation>+ '}'
```

GIR functions are introduced with the `@` sigil and a unique alphanumeric identifier 
namespaced by periods.


GIR Types
========

```
gir-type ::= '@box'? '*'? <silt-type>
```

The syntax of GIR types mirrors that of plain Silt types for simplicity.

## Box Types

For values that require managed storage on the heap, the type `@box T` is used.

***FIXME: EXPAND AFTER DISCUSSION*** 

## Archetypes

An archetype is metadata describing a dynamically-sized runtime entity. They are used
to implement Silt's generics system.

## Address Types

A type may require an in-memory or address-only representation, this is denoted by the 
prefix `*`. Types with this representation fall into one of two general classes:

### Loadable Types

A loadable type is an address type where loading and storing the pointed-to value 
are sensible well-defined operations. These are usually pointers inside data structures or
the projected value of a box type.

### Address-Only Types

An address-only type is an address type where it does not make sense to load or store
the value that may or may not be pointed to by its address. These values must therefore 
be manipulated indirectly by operations such as `copy_address` or `destroy_address`. It
is illegal to have a value of type `T` if `*T` is address-only.

Continuations & Scheduling
=====================

```
continuation ::= <id> ('(' <operand> (';' <operand>)* ')')? ':' <gir-primop-stmt>* <terminator>
gir-primop-stmt ::= (<gir-value-id> '=')? <gir-primop>
```

Because GraphIR uses Continuation-Passing Style, the fundamental abstraction is the
continuation: an independent set of zero or more primitive operations (or primops) and 
a required terminator primop that can never return a value, only transfer the flow of 
control onwards either by branching or by calling a provided continuation value.

Because GraphIR is using a Sea of Nodes representation, by default it is an unordered 
set of references between values. We commonly refer to this representation as "raw" or 
"unscheduled". Before GraphIR can be lowered to LLVM IR, primops and terminators are
packaged together and these packages are ordered with respect to each other in a process
known as "Scheduling". At this point, GraphIR very much resembles LLVM or 
SIL-style IRs, and we refer to it as "scheduled". A "schedule" is a sequence of "scopes"
which are, in-turn, an ordered sequence of continuations.

All textual GraphIR is scheduled GraphIR.

Instruction Set
===========

## Allocation & Deallocation

These instructions allocate and deallocate memory.

### alloca

```
gir-primop ::= 'alloca' <gir-type>

%1 = alloca T
-- %1 has type *T
```

Allocates a region of uninitialized memory that is sufficiently large enough to contain a
value of type `T`. The result of the instruction is the address of the allocated memory.

If the size of `T` must be determined at runtime, the compiler must emit code to potentially
dynamically allocate memory. There is no guarantee that the allocated
memory is located on the stack.

### alloc_box

```
gir-primop ::= 'alloc_box' <gir-type>

%1 = alloc_box T
-- %1 has type @box T
```

Allocates a box on the heap large enough to hold a value of type `T`.

### dealloca

```
gir-primop ::= 'dealloca' <operand>

dealloca %1 : *T
```

Deallocates memory previously allocated by an `alloca` instruction.

### dealloc_box

```
gir-primop ::= 'dealloc_box' <operand>

dealloc_box %1 : @box T
```

Deallocates a heap box.

## Accessing Memory

### load

```
gir-primop ::= 'load' '['<ownership-qualifier>']' <operand> : <gir-type>

%1 = load [take] %0 : *T
-- %1 has type T
```

Loads the value stored at the heap address for the given box. `T` must be a loadable type.

### project_box

```
gir-primop ::= 'project_box' <gir-type>

%1 = project_box %0 : @box T
-- %1 has type *T
```

Given a heap box of type `@box T`, produces the address of the value inside the box.

### store_box

```
gir-primop ::= 'store_box' <gir-value-id> 'to' <operand> : <gir-type>

%2 = store_box %0 to %1 : @box T
-- %2 has type @box T
```

Stores the value `%0` to the heap memory of the box `%1`. This overwrites the value stored
in the box at `%1`, if any.

## Data

These instructions construct and manipulate datatype values.

### data_init

```
gir-primop ::= 'data_init' <gir-type> ';' <qualified-name> ';' (';' <operand>)?

%n = data_init T ; T.constructor ; %0 : U ; %1 : V ; ...
-- %n has type T
```

Creates a loadable value of the given datatype by instantiating the given data constructor.

## Tuples

### tuple

```
gir-primop ::= 'tuple' '(' (<operand> (',' <operand>)*)? ')'

%1 = tuple (%a : A, %b : B, ...)
`````

Creates a tuple value by aggregating multiple values.

### tuple_element_address

```
gir-primop ::= 'tuple_element_address' <operand> ',' <int-literal>

%1 = tuple_element_address %0 : *(T...), 123
```

Given the address of a tuple in memory, derives the address of an element within that value.

## Control Flow

These instructions impose control flow structure on GraphIR by expressing data 
dependencies.  They otherwise do not affect the semantics of the program.

### force_effects

```
gir-primop ::= 'force_effects' <operand> '(' (<operand> (',' <operand>)*)? ')'

%1 = force_effects %retVal (%a : A, %b : B, ...)
```

Construct a "happens-before" relation between multiple nodes in GraphIR by expressing a
data dependency of a result value on the other parameter values.  The result of this operation
is the return value itself.

## Ownership

These instructions implement the core operations of the Silt ownership conventions.

### copy_value

```
gir-primop ::= 'copy_value' <operand>

%1 = copy_value %0 : T
```

Performs a copy of a value of loadable type. The resulting value is independent of the
operand value. For values of trivial type this operation is a no-op.

### destroy_value

```
gir-primop ::= 'destroy_value' <operand>

destroy_value %0 : T
```

Destroys a value of loadable type. For values of trivial type this operation is a no-op.

### copy_address

```
gir-primop ::= 'copy_addr' <gir-value-id> 'to' <operand> : <gir-type>

%2 = copy_address %0 to %1 : *T
```

For loadable types, loads the value at address `%0` from memory and assigns a copy of it
back into memory at address `%1`.  For address-only types, this primop is specialized to
perform an equivalent (often runtime-sanctioned) operation.

### destroy_address

```
gir-primop ::= 'destroy_addr' <operand>

destroy_address %0 : *T
```

Destroys the value in memory at address `%0`.  For loadable types this loads and destroys
the pointed-to value.  For address-only types, this primop is specializd to perform an
equivalent (often runtime-sanctioned) operation.

`destroy_address`  does not deallocate memory, only leaves it uninitialized.

## Terminators

These instructions terminate a continuation. Every continuation must end with a 
terminator as its final primop.

### apply

```
terminator ::= 'apply' <gir-value-id> '(' (<gir-value-id> (';' <gir-value-id>)*)? ')' ':' gir-type

%n = apply %0(%1, %2, ...) : (A, B, ..., (Z) -> _) -> _
```

Transfers control to the continuation `%0`, passing it the given arguments. The type of 
the callee is specified after the argument list. The callee must have function type.

Control does not return to the calling continuation.

### switch_constr

```
'switch_constr' <operand> (';' <qualified-name> ':' <gir-value-id>)*

switch_constr %0 : T ; T.constructor1 : %2 ; T.constructor2 : %3 ; ... ; default %n
```

Conditionally branches to one of several destination continuations based on the tag in a
data type's constructor. If a constructor contains associated data values, those will be
passed to the destination continuation as arguments. For example:

```llvm
module Example where

-- data Nat : Type where
--   zero : Nat
--   suc  : Nat -> Nat

-- _+_ : Nat -> Nat -> Nat
-- zero  + m = m
-- suc n + m = suc (n + m)

@Example._+_ : (Example.Nat ; Example.Nat) -> (Example.Nat) -> _ {
bb0(%0 : Example.Nat; %1 : Example.Nat; %2 : (Example.Nat) -> _):
  %3 = function_ref @bb2
  %4 = function_ref @bb1
  switch_constr %0 : Example.Nat ; Example.Nat.zero : %3 ; Example.Nat.suc : %4
  
bb1(%6 : @box Example.Nat):
  %7 = function_ref @bb0
  %8 = project_box %6 : @box Example.Nat
  %9 = load [copy] %8 : *Example.Nat
  %10 = function_ref @bb3
  apply %7(%9 ; %1 ; %10) : (Example.Nat ; Example.Nat) -> (Example.Nat) -> _
  
bb2:
  %11 = copy_value %1
  destroy_value %1
  destroy_value %0
  apply %2(%11) : (Example.Nat) -> _
  
bb3(%15 : Example.Nat):
  %16 = copy_value %15
  %17 = alloc_box Example.Nat
  %18 = store_box %16 to %17
  %19 = data_init Example.Nat ; Example.Nat.suc ; %18
  destroy_value %1
  destroy_value %0
  apply %2(%19) : (Example.Nat) -> _
} -- end gir function Example._+_
```

Control does not return to the calling continuation.

### unreachable

```
gir-primop ::= 'unreachable'

unreachable
```

Indicates that control flow must not reach the end of the current continuation.

