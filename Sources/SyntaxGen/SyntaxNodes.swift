/// SyntaxNodes.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

let syntaxNodes = [
  /// MARK: Identifiers

  Node("IdentifierList", element: "IdentifierToken"),

  // qualified-name ::= <id> | <id> '.' <qualified-name>
  Node("QualifiedName", element: "QualifiedNamePiece"),

  Node("QualifiedNamePiece", kind: "Syntax", children: [
    Child("name", kind: "IdentifierToken"),
    Child("trailingPeriod", kind: "PeriodToken", isOptional: true)
  ]),


  /// MARK: Modules

  // module-decl ::= 'module' <id> <typed-parameter-list>? 'where' <decl-list>
  // decl-list ::= <decl>
  //             | <decl> <decl-list>

  Node("ModuleDecl", kind: "Decl", children: [
    Child("moduleToken", kind: "ModuleToken"),
    Child("moduleIdentifier", kind: "IdentifierToken"),
    Child("typedParameterList", kind: "TypedParameterList", isOptional: true),
    Child("whereToken", kind: "WhereToken"),
    Child("declList", kind: "DeclList")
  ]),

  Node("DeclList", element: "Decl"),

  /// MARK: Imports

  // qualified-name ::= <id> | <id> '.' <qualified-name>
  // import-decl ::= 'open'? 'import' <qualified-name>

  Node("OpenImportDecl", kind: "Decl", children: [
    Child("openToken", kind: "OpenToken", isOptional: true),
    Child("importToken", kind: "ImportToken"),
    Child("importIdentifier", kind: "IdentifierToken")
  ]),

  Node("ImportDecl", kind: "Decl", children: [
    Child("importToken", kind: "ImportToken"),
    Child("importIdentifier", kind: "IdentifierToken")
  ]),

  /// MARK: Data types

  // data-decl ::= 'data' <id> <typed-parameter-list>? <type-indices>? 'where' <constructor-list>

  Node("DataDecl", kind: "Decl", children: [
    Child("dataToken", kind: "DataToken"),
    Child("dataIdentifier", kind: "IdentifierToken"),
    Child("typedParameterList", kind: "TypedParameterList", isOptional: true),
    Child("typeIndices", kind: "TypeIndices"),
    Child("whereToken", kind: "WhereToken"),
    Child("constructorList", kind: "ConstructorList")
  ]),

  // type-indices ::= ':' <expr>

  Node("TypeIndices", kind: "Syntax", children: [
    Child("colonToken", kind: "ColonToken"),
    Child("indexExpr", kind: "Expr")
  ]),


  // typed-parameter-list ::= <typed-parameter>
  //                       | <typed-parameter> <typed-parameter-list>

  Node("TypedParameterList", element: "TypedParameter"),

  // ascription ::= <id-list> ':' <expr>

  Node("Ascription", kind: "Syntax", children: [
    Child("boundNames", kind: "IdentifierList"),
    Child("colonToken", kind: "ColonToken"),
    Child("typeExpr", kind: "Expr")
  ]),

  // typed-parameter ::= '(' <ascription> ')'

  Node("TypedParameter", kind: "Syntax", children: [
    Child("leftParenToken", kind: "LeftParenToken"),
    Child("ascription", kind: "Ascription"),
    Child("rightParenToken", kind: "RightParenToken")
  ]),

  // constructor-list ::= <constructor-decl>
  //                    | <constructor-decl> <constructor-decl-list>

  Node("ConstructorList", element: "ConstructorDecl"),

  // constructor-decl ::= '|' <ascription>

  Node("ConstructorDecl", kind: "Decl", children: [
    Child("pipeToken", kind: "PipeToken"),
    Child("ascription", kind: "Ascription")
  ]),

  /// MARK: Records

  // record-decl ::= 'record' <id> <typed-parameter-list>? <type-indices>? 'where' <record-element-list>?

  Node("RecordDecl", kind: "Decl", children: [
    Child("recordToken", kind: "RecordToken"),
    Child("recordName", kind: "IdentifierToken"),
    Child("parameterList", kind: "TypedParameterList", isOptional: true),
    Child("typeIndices", kind: "TypeIndices", isOptional: true),
    Child("whereToken", kind: "WhereToken", isOptional: true),
    Child("recordElementList", kind: "RecordElementList")
  ]),

  // record-element-list ::= <record-element>
  //                       | <record-element> <record-element-list>

  Node("RecordElementList", element: "RecordElement"),

  // record-element ::= <field-decl>
  //                  | <function-decl>

  Node("RecordElement", kind: "Syntax", children: []),

  // field-decl ::= 'field' <ascription>

  Node("FieldDecl", kind: "RecordElement", children: [
    Child("fieldToken", kind: "FieldToken"),
    Child("ascription", kind: "Ascription")
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

  /// MARK: Functions

  // function-decl ::= <ascription> <function-clause-list>

  Node("FunctionDecl", kind: "Decl", children: [
    Child("ascription", kind: "Ascription"),
    Child("clauseList", kind: "FunctionClauseList")
  ]),

  // function-clause-list ::= <function-clause>
  //                        | <function-clause> <function-clause-list>

  Node("FunctionClauseList", element: "FunctionClause"),

  // function-clause ::= <id> <pattern-clause-list>? with <expr> '|' <pattern-clause-list>? '=' <expr>
  //                   | <id> <pattern-clause-list>? '=' <expr>

  Node("FunctionClause", kind: "Syntax", children: []),

  Node("NormalFunctionClause", kind: "FunctionClause", children: [
    Child("functionName", kind: "IdentifierToken"),
    Child("patternClauseList", kind: "PatternClauseList", isOptional: true),
    Child("withToken", kind: "WithToken"),
    Child("withExpr", kind: "Expr"),
    Child("withPatternClause", kind: "PatternClauseList", isOptional: true),
    Child("equalsToken", kind: "EqualsToken"),
    Child("rhsExpr", kind: "Expr")
  ]),

  Node("WithRuleFunctionClause", kind: "FunctionClause", children: [
    Child("functionName", kind: "IdentifierToken"),
    Child("patternClauseList", kind: "PatternClauseList", isOptional: true),
    Child("equalsToken", kind: "EqualsToken"),
    Child("rhsExpr", kind: "Expr")
  ]),


  /// MARK: Patterns

  // pattern-clause-list ::= <pattern-clause>
  //                       | <pattern-clause> <patter-clause-list>
  // pattern-clause ::= <expr>

  Node("PatternClauseList", element: "Expr"),

  // Expressions

  // expr ::= <typed-parameter> '->' <expr>
  //        | <basic-expr-list> '->' <expr>
  //        | '\' <binding-list> <expr>
  //        | 'forall' <binding-list> '->' <expr>
  //        | 'let' <decl-list> 'in' <expr>
  //        | <application>
  //        | <basic-expr>

  Node("TypedParameterArrowExpr", kind: "Expr", children: [
    Child("parameter", kind: "TypedParameter"),
    Child("arrowToken", kind: "ArrowToken"),
    Child("outputExpr", kind: "Expr")
  ]),

  Node("BasicExprListArrowExpr", kind: "Expr", children: [
    Child("exprList", kind: "BasicExprList"),
    Child("arrowToken", kind: "ArrowToken"),
    Child("outputExpr", kind: "Expr")
  ]),

  Node("LambdaExpr", kind: "Expr", children: [
    Child("slashToken", kind: "ForwardSlashToken"),
    Child("bindingList", kind: "BindingList"),
    Child("bodyExpr", kind: "Expr")
  ]),

  Node("QuantifiedExpr", kind: "Expr", children: [
    Child("forallToken", kind: "ForallToken"),
    Child("bindingList", kind: "BindingList"),
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
    Child("exprs", kind: "ApplicationExprList")
  ]),

  Node("BasicExpr", kind: "Expr", children: []),

  // application ::= <basic-expr> <application>

  Node("ApplicationExprList", element: "BasicExpr"),

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
    Child("parameterExpr", kind: "BasicExpr"),
    Child("leftBraceToken", kind: "LeftBraceToken"),
    Child("fieldAssignments", kind: "RecordFieldAssignmentList", isOptional: true),
    Child("rightBraceToken", kind: "RightBraceToken")
  ]),
]
