# Mangling GIR 

This file defines the mangling grammar used for a top-level Silt names.  

```
mangled-name ::= '_S' global
```

All silt-mangled names begin with this prefix.

The mangling scheme is a list of 'operators' in post-fix order. For example the mangling 
may start with an identifier but later, a postfix operator defines how this identifier os 
interpreted:

```
4Example3FooD   // The trailing 'D' says that 'Foo' is a data declaration in module 'Example'
```

Operators are either identifiers or a single  character, like `D` for datatype.

Identifiers
=======

```
identifier ::= substitution
identifier ::= natural identifier-string   // identifier without word substitutions
identifier ::= '0' identifier-part         // identifier with word substitutions

identifier-part ::= natural identifier-string
identifier-part ::= [a-z]                  // word substitution (except the last one)
identifier-part ::= [A-Z]                  // last word substitution in identifier

identifier-string ::= identifier-start identifier-char*
identifier-start  ::= [_a-zA-Z]
identifier-char   ::= [_$a-zA-Z0-9]

natural ::= [1-9] [0-9]*
```

All identifiers are run-length encoded sequences of ascii alphanumeric characters.
Note that an identifier may not start with a numeric prefix so as not to conflict with the 
run-length.

If the identifier starts with a digit or an underscore, an additional underscore is inserted.

```
identifier ::= '00' natural '_'? identifier-char+
```

Identifiers that contain non-ASCII characters are encoded using the Punycode algorithm 
specified in RFC 3492, with the modifications that `$` is used as the encoding delimiter, 
and uppercase letters `A` through `J` are used in place of digits `0` through `9` in the 
encoding character set. The mangling then consists of an `00` followed by the run length 
of the encoded string and the encoded string itself. For example, the identifier  
`vergüenza` is mangled to `0012vergenza_JFa`. (The encoding in standard Punycode 
would be `vergenza-95a`)

If the run-length start with a `0` the identifier string contains word substitutions. A word is 
a sub-string of an identifier which contains letters and digits `[A-Za-z0-9]`. Words are 
separated by underscores. In addition a new word begins with an uppercase letter
if the previous character is not an uppercase letter:

```
Abc1DefG2HI          // contains four words 'Abc1', 'Def' and 'G2' and 'HI'
_abc1_def_G2hi       // contains three words 'abc1', 'def' and G2hi
```

The words of all identifiers, which are encoded in the current mangling are
enumerated and assigned to a letter: a = first word, b = second word, etc.

An identifier containing word substitutions is a sequence of run-length encoded
sub-strings and references to previously mangled words.
All but the last word-references are lowercase letters and the last one is an
uppercase letter. If there is no literal sub-string after the last
word-reference, the last word-reference is followed by a `0`.

Let's assume the current mangling already encoded the identifier `AbcDefGHI`

```
07Exampleac1_B    // expands to: MyAbcGHI_Def
```

Because the indices of substitution words is alphabetic, a maximum of 26 words can be
used for substitutions.

Identifiers that contain non-ASCII characters are encoded using the Punycode
algorithm specified in RFC 3492, with the modifications that ``_`` is used
as the encoding delimiter, and uppercase letters A through J are used in place
of digits 0 through 9 in the encoding character set. The mangling then
consists of an ``00`` followed by the run length of the encoded string and the
encoded string itself. For example, the identifier ``vergüenza`` is mangled
to ``0012vergenza_JFa``. (The encoding in standard Punycode would be
``vergenza-95a``)

If the encoded string starts with a digit or an ``_``, an additional ``_`` is
inserted between the run length and the encoded string.

Substitutions
==========

```
// substitution of N+26
substitution ::= 'A' index
// One or more consecutive substitutions of N < 26
substitution ::= 'A' substitution-index* final-substitution-index

substitution-index ::= [a-z]
substitution-index ::= natural [a-z]

final-substitution-index ::= [A-Z]
final-substitution-index ::= natural [A-Z]

index ::= '_'                               // 0
index ::= natural '_'                       // N+1
```


A substitution is a back-reference to a previously mangled entity. The mangling
algorithm maintains a mapping of entities to substitution indices as it runs.

When an entity that can be represented by a substitution is mangled, a substitution is first
looked for in the substitution map, and if it is present, the entity is mangled using the
associated substitution index. Otherwise, the entity is mangled normally, and
it is then added to the substitution map and associated with the next
available substitution index.

If the mangling contains two or more consecutive substitutions, it can be
abbreviated with the `A` substitution. Similar to word-substitutions the
index is encoded as letters, whereas the last letter is uppercase:

```
AaeB      // equivalent to A_A4_A0_
```

Repeated substitutions are encoded with a natural number prefix:

```
A3a2B     // equivalent to AaaabB
```

Declaration Contexts
================

These manglings identify the enclosing context in which an entity was declared,
such as its enclosing module, function, data type, or record.

```
context ::= module
context ::= entity

module ::= identifier
```

Entities
======

```
entity ::= datatype
entity ::= function
entity ::= record

datatype ::= identifier 'D'

function ::= identifier function-signature 'F'
function-signature ::= signature-types signature-types // return type then parameter type

signature-types ::= type
signature-types ::= empty-list    

record ::= identifier 'R'

empty-list ::= 'y'
```

Types
====

```
type ::= 'T' // Type type
type ::= 'B' // bottom type
type ::= type-list

type-list ::= type '_' type*
type-list ::= empty-list
```
