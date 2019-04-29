The Miner's Canary: A Tour of the Silt Compiler
===================================

The Silt compiler draws inspiration for its infrastructure from the [LLVM
project](https://llvm.org).  Each major component of the compiler finds its
focus in a library, and each library in turn forms interconnections with other
libraries above it in the stack.  This keeps the compiler modular and nimble and
allows us to design tests that target any individual layer.

Rheological Structure
================

The Silt compiler's component libraries are organized according to the layers of
Earth:

```ascii
  \########################################################/            
   \######################################################/ LITHOSPHERE              
    \####################################################/               
     \**/**/**/**/**/**/**/**/**/**/**/**/**/**/**/**/**/                
      \/**/**/**/**/**/**/**/**/**/**/**/**/**/**/**/**/ CRUST               
       \/**/**/**/**/**/**/**/**/**/**/**/**/**/**/**//                  
        \********************************************/                   
         \******************************************/ MOHO                   
          \****************************************/                     
           \**************************************/                      
            \,.,.,.,.,.,.,.,.,.,.,.,.,.,.,.,.,.,./                       
             \.,.,.,.,.,.,.,.,.,.,.,.,.,.,.,.,.,/                        
              \,.,.,.,.,.,.,.,.,.,.,.,.,.,.,.,./                         
               \.,.,.,.,.,.,.,.,.,.,.,.,.,.,.,/ MANTLE                         
                \,.,.,.,.,.,.,.,.,.,.,.,.,.,./                           
                 \.,.,.,.,.,.,.,.,.,.,.,.,.,/                            
                  \************************/                             
                   \**********************/ MESOSPHERE                             
                    \********************/                               
                     \,,,,,,,,,,,,,,,,, /                                
                      \,,,,,,,,,,,,,,,,/                                 
                       \,,,,,,,,,,,,,,/ OUTER CORE                                 
                        \,,,,,,,,,,,,/                                   
                         \........../                                    
                          \......../                                     
                           \....../ INNER CORE                                    
                            \..../                                      
                             \../                                        
                              \/                                       
```

Functionality at each layer can be broadly classified as such:

1. **Lithosphere**
    - Defines the userland AST based on [libSyntax](https://github.com/apple/swift/blob/master/lib/Syntax/README.md)
    - Provides a Swift tool, SyntaxGen, to programmatically generate the AST
2. **Crust**
    - First processing of `.silt` files and produces an AST with perfect source
      fidelity
    - Defines a Lexer to tokenize the input stream
    - Defines a Shiner to translate the token stream to a context-free scoped
      token stream
    - Defines a Parser that translates the context-free token stream to an AST
3. **Moho**
    - Takes the raw AST and performs name binding.
    - Resolves any (open) imports
    - Rebinds any expressions involving mixfix operators
    - Performs scope checking to ensure the AST is well-scoped
    - Lowers the user's AST to a simpler intermediate AST
4. **Mantle**
    - Performs type checking and elaboration
    - Elaboration lowers the simplified user AST to a Core Type Theory (TT)
    - Type checking validates TT terms by producing and solving constraints
    - Well-scoped, well-typed TT terms are emitted to lower phases
5. **Mesosphere** 
    - Simplification and lowering of TT terms and types
    - Lowers TT terms to a GraphIR similar to [Thorin GraphIR](https://github.com/AnyDSL/thorin)
    - Decides early calling conventions and type layouts
6. **Outer Core**
    - Schedules and canonicalizes GraphIR 
    - Performs optimizations on the GraphIR structure
7. **Inner Core**
    - Lowers GraphIR terms to LLVM IR
    - Schedules any remaining optimizations
    - Passes IR to LLVM for final processing

Additional Strata
=============

A compiler is more than just a series of phases, though.  Silt includes a number of
libraries that provide utilities for the different phases and tooling to make hacking on
the compiler easier

## Libraries

### Boring

The Boring framework is where the silt driver and associated subtools live.  The driver
will eventually include a build system that is responsible for scheduling and executing
individual silt frontend invocations.  For now, only single frontend invocations are 
supported, but we hope to split the frontend out as a separate subcommand very soon.

### Drill

The Drill is where the silt frontend is defined.  It is responsible for converting its argument
list into the appropriate compilation action, then stitching together the passes given by
the layers above into a cohesive compilation pipeline.

### Seismography

Seismography is where the GraphIR AST and utilities for manipulating that AST live.  It
includes the core data definitions for GIR declarations such as Continuations and 
PrimOps, but also utilities like the name manglers and the initial type lowering algorithm.

### Ferrite

Ferrite is the silt runtime.  It is written in C++ with C entrypoints that are used by the 
InnerCore to perform runtime manipulation of values and metadata.

## Utilities

### SyntaxGen

SyntaxGen is a tool for programmatically generating the silt surface AST.  The tool is 
written entirely in Swift, down to the way we define the schema that generates the AST.
There are two primary schemata that define the silt AST - 
[the syntax nodes](SyntaxGen/SyntaxNodes.swift) and 
[the token nodes](SyntaxGen/TokenNodes.swift).  

Token nodes correspond to libSyntax token definitions and can either be raw keywords,
punctuation marks, or be a general class of token with structurally-associated data 
(e.g. identifiers have an associated string).  An example of each is given below

```swift
let tokenNodes = [
  // Example punctuation token declarations
  Token(name: "Equals", .punctuation("=")),
  Token(name: "LeftParen", .punctuation("(")),
  Token(name: "RightParen", .punctuation(")")),
  // ...

  // Example keyword token declarations
  Token(name: "Module", .keyword("module")),
  Token(name: "Import", .keyword("import")),
  // ...

  // Example of associating values with tokens
  Token(name: "Identifier", .associated("String")),
  // ...
]
```

Syntax nodes correspond to libSyntax node definitions and may either be a tree with
children or a collection of other syntax elements.  Syntax nodes always have as their
root class one of a pre-defined set of root syntax nodes.  These are, in general, 
`Decl`, `Expr`,  and `BasicExpr`.

Declaring new syntax nodes or editing other syntax nodes is reminiscent of the token
schema given above.  An example is the following

```swift
let syntaxNodes = [

  // Defines a Syntax Collection that has IdentifierTokens as elements
  Node("IdentifierList", element: "IdentifierToken"),
  // ...

  // Defines a Syntax Node for import declarations.
  Node("ImportDecl", kind: "Decl", children: [
    Child("importToken", kind: "ImportToken"),
    Child("importIdentifier", kind: "QualifiedName"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),
]
```

Modifying the libSyntax AST is as easy as changing one of these two schema and running

```bash
swift run SyntaxGen -o ./Sources/Lithosphere/
```

### Lite

Lite is our clone of the [LLVM Integrated Tester](https://llvm.org/docs/CommandGuide/lit.html),
rewritten in Swift. Lite is written as [a Swift package](https://github.com/llvm-swift/Lite) to 
enable custom tooling to be written on top of the executor. 

To run all the ingration tests with lite, change to the root directory of this repository and
invoke

```swift
swift run lite
```

Lite will automatically discover and run any tests in a file with the extension `.silt` or 
`.gir` that include at least one `RUN:` line.  An example test is given that runs the silt 
diagnostic  verifier  on the current test file

```silt
-- RUN: %silt --verify typecheck %s

module absurd where

data NotEmpty : Type where
  inhabited : NotEmpty

no-magic : {A : Type} -> (x : NotEmpty) -> A 
no-magic ()
-- expected-error@-1 {{absurd pattern of type 'absurd.NotEmpty' in clause should not have possible valid patterns}}
-- expected-note@-2 {{possible valid pattern: 'absurd.NotEmpty.inhabited'}}
```

To run all the unit tests, invoke

```swift
swift test
```

### FileCheck

FileCheck is similarly provided as a library that mimics the 
[LLVM FileCheck Utility](https://llvm.org/docs/CommandGuide/FileCheck.html).  We 
provide a clone of FileCheck with near feature-parity for use in the test suite.  An example
integration test that runs FileCheck on its output is the following

```silt
-- RUN: %silt %s --dump parse-gir 2>&1 | %FileCheck %s

-- CHECK: module unreachable where
module unreachable where

@unreachable : () -> _ {
bb0:
-- CHECK: unreachable
  unreachable
}
```
