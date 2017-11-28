/// SyntaxNodes.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

let syntaxNodes = [
  // MARK: Identifiers

  Node("IdentifierList", element: "IdentifierToken"),

  // qualified-name ::= <id> | <id> '.' <qualified-name>
  Node("QualifiedName", element: "QualifiedNamePiece"),

  Node("QualifiedNamePiece", kind: "Syntax", children: [
    Child("name", kind: "IdentifierToken"),
    Child("trailingPeriod", kind: "PeriodToken", isOptional: true)
  ]),


  // MARK: Modules

  // module-decl ::= 'module' <id> <typed-parameter-list>? 'where' <decl-list>
  // decl-list ::= <decl>
  //             | <decl> <decl-list>

  Node("ModuleDecl", kind: "Decl", children: [
    Child("moduleToken", kind: "ModuleToken"),
    Child("moduleIdentifier", kind: "QualifiedName"),
    Child("typedParameterList", kind: "TypedParameterList"),
    Child("whereToken", kind: "WhereToken"),
    Child("leftBraceToken", kind: "LeftBraceToken"),
    Child("declList", kind: "DeclList"),
    Child("rightBraceToken", kind: "RightBraceToken"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),

  Node("DeclList", element: "Decl"),

  // MARK: Imports

  // qualified-name ::= <id> | <id> '.' <qualified-name>
  // import-decl ::= 'open'? 'import' <qualified-name>

  Node("OpenImportDecl", kind: "Decl", children: [
    Child("openToken", kind: "OpenToken", isOptional: true),
    Child("importToken", kind: "ImportToken"),
    Child("importIdentifier", kind: "QualifiedName")
  ]),

  Node("ImportDecl", kind: "Decl", children: [
    Child("importToken", kind: "ImportToken"),
    Child("importIdentifier", kind: "QualifiedName")
  ]),

  // MARK: Data types

  // data-decl ::= 'data' <id> <typed-parameter-list>? <type-indices>? 'where' '{' <constructor-list> '}' ';'

  Node("DataDecl", kind: "Decl", children: [
    Child("dataToken", kind: "DataToken"),
    Child("dataIdentifier", kind: "IdentifierToken"),
    Child("typedParameterList", kind: "TypedParameterList"),
    Child("typeIndices", kind: "TypeIndices"),
    Child("whereToken", kind: "WhereToken"),
    Child("leftBraceToken", kind: "LeftBraceToken"),
    Child("constructorList", kind: "ConstructorList"),
    Child("rightBraceToken", kind: "RightBraceToken"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),

  // type-indices ::= ':' <expr>

  Node("TypeIndices", kind: "Syntax", children: [
    Child("colonToken", kind: "ColonToken"),
    Child("indexExpr", kind: "Expr")
  ]),


  // typed-parameter-list ::= <typed-parameter>
  //                        | <typed-parameter> <typed-parameter-list>

  Node("TypedParameterList", element: "TypedParameter"),

  // ascription ::= <id-list> ':' <expr>

  Node("Ascription", kind: "Syntax", children: [
    Child("boundNames", kind: "IdentifierList"),
    Child("colonToken", kind: "ColonToken"),
    Child("typeExpr", kind: "Expr")
  ]),

  // typed-parameter ::= '(' <ascription> ')'
  //                   | '{' <ascription> '}'

  Node("TypedParameter", kind: "Syntax", children: []),

  Node("ExplicitTypedParameter", kind: "TypedParameter", children: [
    Child("leftParenToken", kind: "LeftParenToken"),
    Child("ascription", kind: "Ascription"),
    Child("rightParenToken", kind: "RightParenToken")
  ]),

  Node("ImplicitTypedParameter", kind: "TypedParameter", children: [
    Child("leftBraceToken", kind: "LeftBraceToken"),
    Child("ascription", kind: "Ascription"),
    Child("rightBraceToken", kind: "RightBraceToken")
  ]),

  // constructor-list ::= <constructor-decl>
  //                    | <constructor-decl> ';' <constructor-decl-list>

  Node("ConstructorList", element: "ConstructorDecl"),

  // constructor-decl ::= '|' <ascription>

  Node("ConstructorDecl", kind: "Decl", children: [
    Child("pipeToken", kind: "PipeToken"),
    Child("ascription", kind: "Ascription"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),

  // MARK: Records

  // record-decl ::= 'record' <id> <typed-parameter-list>? <type-indices>? 'where' '{' <record-element-list>? '}' ';'

  Node("RecordDecl", kind: "Decl", children: [
    Child("recordToken", kind: "RecordToken"),
    Child("recordName", kind: "IdentifierToken"),
    Child("parameterList", kind: "TypedParameterList"),
    Child("typeIndices", kind: "TypeIndices", isOptional: true),
    Child("whereToken", kind: "WhereToken"),
    Child("leftParenToken", kind: "LeftParenToken"),
    Child("recordElementList", kind: "RecordElementList"),
    Child("rightParenToken", kind: "RightParenToken"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),

  // record-element-list ::= <record-element>
  //                       | <record-element> ';' <record-element-list>

  Node("RecordElementList", element: "Decl"),

  // record-element ::= <field-decl>
  //                  | <function-decl>
  //                  | <record-constructor-decl>

  // field-decl ::= 'field' <ascription>

  Node("FieldDecl", kind: "Decl", children: [
    Child("fieldToken", kind: "FieldToken"),
    Child("ascription", kind: "Ascription"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),

  // record-constructor-decl ::= 'constructor' <id>

  Node("RecordConstructorDecl", kind: "Decl", children: [
    Child("constructorToken", kind: "ConstructorToken"),
    Child("constructorName", kind: "IdentifierToken"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),

  // record-field-assignment-list ::= <record-field-assignment>
  //                                | <record-field-assignment> ';' <record-field-assignment-list>

  Node("RecordFieldAssignmentList", element: "RecordFieldAssignment"),

  // record-field-assignment ::= <id> '=' <expr>

  Node("RecordFieldAssignment", kind: "Syntax", children: [
    Child("fieldName", kind: "IdentifierToken"),
    Child("equalsToken", kind: "EqualsToken"),
    Child("fieldInitExpr", kind: "Expr"),
    Child("trailingSemicolon", kind: "SemicolonToken", isOptional: true)
  ]),

  // MARK: Functions

  // function-decl ::= <ascription>

  Node("FunctionDecl", kind: "Decl", children: [
    Child("ascription", kind: "Ascription"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),

  // function-clause ::= <basic-expr-list> with <expr> '|' <basic-expr-list>? '=' <expr>
  //                   | <basic-expr-list> '=' <expr>

  Node("FunctionClauseDecl", kind: "Decl", children: []),

  Node("WithRuleFunctionClauseDecl", kind: "FunctionClauseDecl", children: [
    Child("basicExprList", kind: "BasicExprList"),
    Child("withToken", kind: "WithToken"),
    Child("withExpr", kind: "Expr"),
    Child("withPatternClause", kind: "BasicExprList", isOptional: true),
    Child("equalsToken", kind: "EqualsToken"),
    Child("rhsExpr", kind: "Expr"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),

  Node("NormalFunctionClauseDecl", kind: "FunctionClauseDecl", children: [
    Child("basicExprList", kind: "BasicExprList"),
    Child("equalsToken", kind: "EqualsToken"),
    Child("rhsExpr", kind: "Expr"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),

  // MARK: Fixity

  // fixity-decl ::= 'infix' <int> <id-list>
  //               | 'infixl' <int> <id-list>
  //               | 'infixr' <int> <id-list>
  Node("FixityDecl", kind: "Decl", children: []),

  Node("NonFixDecl", kind: "FixityDecl", children: [
    Child("infixToken", kind: "InfixToken"),
    Child("precedence", kind: "IdentifierToken"),
    Child("names", kind: "IdentifierList"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),
  Node("LeftFixDecl", kind: "FixityDecl", children: [
    Child("infixlToken", kind: "InfixlToken"),
    Child("precedence", kind: "IdentifierToken"),
    Child("names", kind: "IdentifierList"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),
  Node("RightFixDecl", kind: "FixityDecl", children: [
    Child("infixrToken", kind: "InfixrToken"),
    Child("precedence", kind: "IdentifierToken"),
    Child("names", kind: "IdentifierList"),
    Child("trailingSemicolon", kind: "SemicolonToken"),
  ]),

  // MARK: Patterns

  // pattern-clause-list ::= <pattern-clause>
  //                       | <pattern-clause> <patter-clause-list>
  // pattern-clause ::= <expr>

  Node("PatternClauseList", element: "Expr"),

  // Expressions

  // expr ::= <typed-parameter-list> '->' <expr>
  //        | <basic-expr-list> '->' <expr>
  //        | '\' <binding-list> <expr>
  //        | 'forall' <typed-parameter-list> '->' <expr>
  //        | 'let' <decl-list> 'in' <expr>
  //        | <application>
  //        | <basic-expr>

  Node("TypedParameterArrowExpr", kind: "Expr", children: [
    Child("parameters", kind: "TypedParameterList"),
    Child("arrowToken", kind: "ArrowToken"),
    Child("outputExpr", kind: "Expr")
  ]),

  Node("LambdaExpr", kind: "Expr", children: [
    Child("slashToken", kind: "ForwardSlashToken"),
    Child("bindingList", kind: "BindingList"),
    Child("arrowToken", kind: "ArrowToken"),
    Child("bodyExpr", kind: "Expr")
  ]),

  Node("QuantifiedExpr", kind: "Expr", children: [
    Child("forallToken", kind: "ForallToken"),
    Child("bindingList", kind: "TypedParameterList"),
    Child("arrowToken", kind: "ArrowToken"),
    Child("outputExpr", kind: "Expr")
  ]),

  Node("LetExpr", kind: "Expr", children: [
    Child("letToken", kind: "LetToken"),
    Child("declList", kind: "DeclList"),
    Child("inToken", kind: "InToken"),
    Child("outputExpr", kind: "Expr")
  ]),

  Node("ApplicationExpr", kind: "Expr", children: [
    Child("exprs", kind: "BasicExprList")
  ]),

  Node("BasicExpr", kind: "Expr", children: []),

  // application ::= <basic-expr> <application>

  // binding-list ::= <qualified-name>
  //                | <typed-parameter>
  //                | <qualified-name> <binding-list>
  //                | <typed-parameter> <binding-list>

  Node("BindingList", element: "Binding"),

  Node("Binding", kind: "Syntax", children: []),

  Node("NamedBinding", kind: "Binding", children: [
    Child("name", kind: "QualifiedName")
  ]),

  Node("TypedBinding", kind: "Binding", children: [
    Child("parameter", kind: "TypedParameter")
  ]),

  // basic-expr-list ::= <basic-expr>
  //                  | <basic-expr> <basic-expr-list>

  Node("BasicExprList", element: "BasicExpr"),

  // basic-expr ::= <qualified-name>
  //              | '_'
  //              | 'Type'
  //              | '(' <expr> ')'
  //              | 'record' <basic-expr>? '{' <record-field-assignment-list>? '}'

  Node("NamedBasicExpr", kind: "BasicExpr", children: [
    Child("name", kind: "QualifiedName")
  ]),

  Node("UnderscoreExpr", kind: "BasicExpr", children: [
    Child("underscoreToken", kind: "UnderscoreToken")
  ]),

  Node("TypeBasicExpr", kind: "BasicExpr", children: [
    Child("typeToken", kind: "TypeToken")
  ]),

  Node("ParenthesizedExpr", kind: "BasicExpr", children: [
    Child("leftParenToken", kind: "LeftParenToken"),
    Child("expr", kind: "Expr"),
    Child("rightParenToken", kind: "RightParenToken")
  ]),

  Node("RecordExpr", kind: "BasicExpr", children: [
    Child("recordToken", kind: "recordToken"),
    Child("parameterExpr", kind: "BasicExpr", isOptional: true),
    Child("leftBraceToken", kind: "LeftBraceToken"),
    Child("fieldAssignments", kind: "RecordFieldAssignmentList"),
    Child("rightBraceToken", kind: "RightBraceToken")
  ]),
]
