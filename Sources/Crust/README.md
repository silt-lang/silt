The Crust library implements the parser, lexer, and shiner to transform source
files into an abstract syntax tree (AST).

Introduction
============

Lexing and parsing are bog-standard operations for any compiler and Silt is no
different.  Where we diverge from the status quo is in the Lexer and Shiner.
Because our AST preserves all trivia, the lexer does not discard non-token
entities.  In addition, because our surface grammar is context sensitive but our
parser only recognizes a context-free input, we interpose a phase between Lexing
and Parsing we call Shining.  We review each in turn:

Lexing
======

Lexing is the process of reading in input file(s) and transforming them into
a higher-level stream of tokens.  Tokens bear information on the parts of the
source that are relevant to the rest of the compiler: identifiers and other
non-whitespace characters.  However, because our AST represents the source text
with 100% fidelity, our lexer must take care to gather whitespace, comments, and
other trivia along with the token stream.

Shining
=======

Shining is the process of transforming the surface language into a context-free
explicitly-scoped input stream suitable for parser.  The rules of shining are
roughly the same as the ones from The [Haskell 98
Report](https://www.haskell.org/onlinereport/syntax-iso.html#layout) with some
Silt-specific simplifications and modifications.

Silt, unlike other languages in the ML family, is *whitespace agnostic*.  This
means a Silt program may be written with tabs, spaces, or any combination of the
two *so long as the user is consistent*.  The rules of layout appear later in
this document.

Parsing
=======

Now that the input stream is explicitly-scoped, the parser processes the token
stream into an AST.  We implement a standard recursive-descent parser that makes
affordances for diagnostics and recovery.

Layout
======

As stated before, Silt is *whitespace agnostic* and only demands consistency.
To make clear what we mean by this, we define the rules of the Shiner's layout
process:

## Terminology

### Whitespace Sequences

For a token `<t>`, let the leading trivia before `<t>`, excluding line comments,
and up to the nearest newline character be defined as its *(leading) whitespace
sequence* `[ws]`.  `[ws]` is an array of spaces and tab characters in the order
in which the user wrote them in the source file.

### Whitespace Equivalence

Two tokens with whitespace sequences `[ws1]<t1>` and `[ws2]<t2>` shall be
considered to have *equivalent (leading) whitespace* if `[ws1]` and `[ws2]`
contain the same number of tabs and spaces in any order.

### Whitespace Equality

Two tokens with whitespace sequences `[ws1]<t1>` and `[ws2]<t2>` shall be
considered to have *equal (leading) whitespace* if `[ws1]` and `[ws2]` contain the
same number of tabs and spaces in the same order.

### Whitespace Ordering

For two tokens with whitespace sequences `[ws1]<t1>` and `[ws2]<t2>` we say
"`<t2>` is at least as indented as `<t1>`" if their respective leading
whitespace is equivalent OR an initial prefix the length of `[ws1]` in `[ws2]`
is equivalent to `[ws1]`.  This ordering is undefined if the equivalent initial
sequence cannot be identified.

## The Rules of Layout (The Shining)

Let `[ws]<t>` notate a generic token with whitespace sequence `[ws]`. We write `<t>`
or literals like `'a'` when this sequence is not needed.

Suppose the whitespace sequence `[ws]` contains a newline. We notate this `[ws]*`.

The operator `Length(*)` acts on a whitespace sequence `[ws]` and returns the sum of
the number of tabs and spaces in the sequence.

The shining procedure `Shine(*, *)` is defined recursively on a stream of tokens,
ts, and a layout stack ls. The layout stack maintains the invariant that, for
`(ls : l2 : l1)`, `l1` is *strictly more indented* than `l2`.

```ascii
Shine [] [] = []
Shine [] (ls : l) = '}'  :  Shine [] ls
Shine (<t> : []) [] = [t]

Shine ([ws1]*<t> : ts) (ls : [ws2]) = ';' : <t>  :  (Shine ts (ls : [ws1]*))   | if [ws1] = [ws2]
                                    = '}'  :  (Shine (<t> : ts) ls) | if [ws1] < [ws2]
                                    = <t> : Shine ts (ls : [ws1]*) | otherwise
  
Shine ('where' : '{' : [ws1]<t> : ts) (ls : [ws2]) = 'where' : '{'  :  <t> : Shine ts (ls : [ws])      | if [ws1] > [ws2]
                                                   = 'where' : '{' : '}' : Shine (t : ts) (ls : [ws2]) | otherwise                             
Shine ('where' : [ws]<t> : ts) (ls : l) = 'where' : '{' : <t> : Shine ts (ls : [ws]) | if [ws1] > [ws2]

Shine ('where' : '{' : [ws]<t> : ts) ls = 'where' : '{'  :  <t> : Shine ts (ls : [ws])
Shine ('where' : [ws]<t> : ts) ls = 'where' : '{' : <t> : Shine ts (ls : [ws])  

Shine ('}' : ts) (ls : [ws]) = '}' : Shine ts ls
 
Shine (<t> : ts) ls = <t> : Shine ts ls
```

