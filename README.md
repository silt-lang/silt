# silt [![Build Status](https://travis-ci.org/silt-lang/silt.svg?branch=master)](https://travis-ci.org/silt-lang/silt)

Silt is an in-progress dependently typed functional programming language. Its
syntax and type system are reminiscent of Idris and Agda, but it compiles
directly to native code through LLVM. We aim for silt to be GC-free by
leveraging stack allocation and lowering to a linearly-typed intermediate
representation that tracks object lifetimes prior to backend code generation.

# Building

Silt builds with the Swift Package Manager. Clone the repository and run
```bash
swift build
```
and an executable will be produced at `.build/debug/silt`.

# License

Silt is released under the MIT License, a copy of which is available in this
repository.

# Contributing

We welcome contributions from programmers of all backgrounds and experience
levels. We've strived to create an environment that encourages learning through
contribution, and we pledge to always treat contributors with the respect they
deserve. We have adopted the Contributor Covenant as our code of conduct,
which can be read in this repository.

# Authors

Robert Widmann ([@CodaFi](https://github.com/codafi))
Harlan Haskins ([@harlanhaskins](https://github.com/harlanhaskins))