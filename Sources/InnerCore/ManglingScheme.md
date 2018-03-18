# GIR Mangling Scheme

This file defines the mangling grammar used for a top-level Silt continuation,
module, record, and data type.

## Special Escaping Rules

All identifiers will be prefixed with the byte-length of the identifier when
they appear in mangled names.
If a name contains any non-ASCII characters, it will be prefixed with `X` and be
[punycode](https://en.wikipedia.org/wiki/Punycode)-encoded. The length will
represent the UTF-8 byte length of the punycode-encoded string.

Example:
```
hello -> 5hello
test🔥 -> X10test_oeHDc
```

## Type Mangling

Silt types will be mangled according to the following pseudocode rules.

### Record Types

```
mangle-record-type(name, indices) ::= 'R' len(name) name mangle-indices(indices)
```

### Data Types

```
mangle-data-type(name, indices) ::= 'D' len(name) name mangle-indices(indices)
```

### Metadata Types

```
mangle-opaque-metadata-type ::= 'O'
mangle-metadata-type(underlying) ::= 'M' mangle-type(underlying)
```

#### Example

### Function Types

```
mangle-function-type(parameters, return) ::= 
  'F' mangle-types(parameters) 'r' mangle-type(return)
```

#### Example

```
(Nat, 💩) -> Bool -> Nat = FD3NatDX4lsIhFD4BoolrD3Nat
```