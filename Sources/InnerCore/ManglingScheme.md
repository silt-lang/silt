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

Top-level Silt types will be mangled according to the following pseudocode rules.

### Record Types

```
mangle-record-type(name, indices) ::= 'R' mangle-id(indices)
```

### Data Types

```
mangle-data-type(name, indices) ::= 'D' mangle-id(name)
```