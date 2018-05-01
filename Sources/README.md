The Miner's Canary: A Tour of the Silt Compiler
===============================================

The Silt compiler draws inspiration for its infrastructure from the [LLVM
project](https://llvm.org).  Each major component of the compiler finds its
focus in a library, and each library in turn forms interconnections with other
libraries above it in the stack.  This keeps the compiler modular and nimble and
allows us to design tests that target any individual layer.

Rheological Structure
=====================

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

