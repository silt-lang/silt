The Lithosphere library contains the sources for libSyntax and the diagnostic
engine.

Introduction 
============

libSyntax is a modern immutable abstraxt syntax tree (AST) oriented towards 100%
syntactic fidelity.  This means the AST tracks whitespace, comments, and other
trivia natively and is capable of round-tripping syntax from source to AST and
back again with no loss of information.  In addition, immutability means that
multiple consumers may freely share access to the same tree.

Immutability 
============

A core feature of the AST is immutability.  However, ASTs often require
manipulation, either by compilers or by tooling.  To support arbitrary
"modification" of the original tree, libSyntax provides setters that create
functionally distinct ASTs.  To keep this process efficient, the syntax tree
modifies only those nodes that need to be changed and keeps as much of the
original structure intact as possible.

Structuring Syntax Trees
========================

The root class of all pieces of syntax is called, perhaps unimaginatively,
`Syntax`.  The library further specializes `Syntax` into the `SyntaxCollection`
class for nodes that need to hold on to a dynamically-sized vector of other
syntax nodes.

To create subclasses of `Syntax` to represents parts of the Silt AST, we have
built a tool called `SyntaxGen` that automates the process of translating
a specification written in Swift to libSyntax nodes.  For further information
on adding or modifying the Silt AST, see the documentation in SyntaxGen.

Diagnostics
===========

Rich diagnostics are an important goal for the Silt compiler.  To that end, we
have a diagnostics engine and DSL that makes creating well-typed diagnostics
easy.  To produce diagnostics, create an instance of `DiagnosticEngine`, or
recieve one from the prevailing `PassContext`.  Spawning a diagnostic is as easy
as creating a new extension to `Diagnostic.Message` and providing an instance
that creates a formatted diagnostic.  For example

```swift
import Lithosphere

extension Diagnostic.Message {
    // Declares an error that formats a `Name`.
    static func nameShadows(_ n: Name) -> Diagnostic.Message {
        return Diagnostic.Message(.error, "cannot shadow name '\(n)'")
    }

    // Declares a note that formats a `Name.
    static func shadowsOriginal(_ n: Name) -> Diagnostic.Message {
        return Diagnostic.Message(.note, "first declaration of '\(n)' occurs here")
    }
}
```

To emit this diagnostic with the attached note, call
`engine.diagnose(_:node:actions:)` like so

```swift
self.engine.diagnose(.nameShadows(name), node: funcDecl.ascription) {
    $0.note(.shadowsOriginal(name), node: nodeMap[name])
}
```

