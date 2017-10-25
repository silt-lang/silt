/// SyntaxKind.swift
/// Automatically generated by SyntaxGen. Do not edit!
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
public enum SyntaxKind {
  case token
  case unknown
  case identifierList
  case qualifiedName
  case qualifiedNamePiece
  case moduleDecl
  case declList
  case openImportDecl
  case importDecl
  case dataDecl
  case typeIndices
  case typedParameterList
  case ascription
  case typedParameter
  case explicitTypedParameter
  case implicitTypedParameter
  case constructorList
  case constructorDecl
  case recordDecl
  case recordElementList
  case fieldDecl
  case recordFieldAssignmentList
  case recordFieldAssignment
  case functionDecl
  case functionClauseList
  case functionClause
  case withRuleFunctionClause
  case normalFunctionClause
  case patternClauseList
  case typedParameterArrowExpr
  case basicExprListArrowExpr
  case lambdaExpr
  case quantifiedExpr
  case letExpr
  case applicationExpr
  case basicExpr
  case applicationExprList
  case bindingList
  case binding
  case namedBinding
  case typedBinding
  case basicExprList
  case namedBasicExpr
  case underscoreExpr
  case typeBasicExpr
  case parenthesizedExpr
  case recordExpr
}

extension Syntax {
  /// Creates a Syntax node from the provided RawSyntax using the
  /// appropriate Syntax type, as specified by its kind.
  /// - Parameters:
  ///   - raw: The raw syntax with which to create this node.
  ///   - root: The root of this tree, or `nil` if the new node is the root.
  static func fromRaw(_ raw: RawSyntax) -> Syntax {
    let data = SyntaxData(raw: raw)
    return make(root: nil, data: data)
  }

  /// Creates a Syntax node from the provided SyntaxData using the
  /// appropriate Syntax type, as specified by its kind.
  /// - Parameters:
  ///   - root: The root of this tree, or `nil` if the new node is the root.
  ///   - data: The data for this new node.
  static func make(root: SyntaxData?, data: SyntaxData) -> Syntax {
    let root = root ?? data
    switch data.raw.kind {
    case .token: return TokenSyntax(root: root, data: data)
    case .unknown: return Syntax(root: root, data: data)
    case .identifierList:
      return IdentifierListSyntax(root: root, data: data)
    case .qualifiedName:
      return QualifiedNameSyntax(root: root, data: data)
    case .qualifiedNamePiece:
      return QualifiedNamePieceSyntax(root: root, data: data)
    case .moduleDecl:
      return ModuleDeclSyntax(root: root, data: data)
    case .declList:
      return DeclListSyntax(root: root, data: data)
    case .openImportDecl:
      return OpenImportDeclSyntax(root: root, data: data)
    case .importDecl:
      return ImportDeclSyntax(root: root, data: data)
    case .dataDecl:
      return DataDeclSyntax(root: root, data: data)
    case .typeIndices:
      return TypeIndicesSyntax(root: root, data: data)
    case .typedParameterList:
      return TypedParameterListSyntax(root: root, data: data)
    case .ascription:
      return AscriptionSyntax(root: root, data: data)
    case .typedParameter:
      return TypedParameterSyntax(root: root, data: data)
    case .explicitTypedParameter:
      return ExplicitTypedParameterSyntax(root: root, data: data)
    case .implicitTypedParameter:
      return ImplicitTypedParameterSyntax(root: root, data: data)
    case .constructorList:
      return ConstructorListSyntax(root: root, data: data)
    case .constructorDecl:
      return ConstructorDeclSyntax(root: root, data: data)
    case .recordDecl:
      return RecordDeclSyntax(root: root, data: data)
    case .recordElementList:
      return RecordElementListSyntax(root: root, data: data)
    case .fieldDecl:
      return FieldDeclSyntax(root: root, data: data)
    case .recordFieldAssignmentList:
      return RecordFieldAssignmentListSyntax(root: root, data: data)
    case .recordFieldAssignment:
      return RecordFieldAssignmentSyntax(root: root, data: data)
    case .functionDecl:
      return FunctionDeclSyntax(root: root, data: data)
    case .functionClauseList:
      return FunctionClauseListSyntax(root: root, data: data)
    case .functionClause:
      return FunctionClauseSyntax(root: root, data: data)
    case .withRuleFunctionClause:
      return WithRuleFunctionClauseSyntax(root: root, data: data)
    case .normalFunctionClause:
      return NormalFunctionClauseSyntax(root: root, data: data)
    case .patternClauseList:
      return PatternClauseListSyntax(root: root, data: data)
    case .typedParameterArrowExpr:
      return TypedParameterArrowExprSyntax(root: root, data: data)
    case .basicExprListArrowExpr:
      return BasicExprListArrowExprSyntax(root: root, data: data)
    case .lambdaExpr:
      return LambdaExprSyntax(root: root, data: data)
    case .quantifiedExpr:
      return QuantifiedExprSyntax(root: root, data: data)
    case .letExpr:
      return LetExprSyntax(root: root, data: data)
    case .applicationExpr:
      return ApplicationExprSyntax(root: root, data: data)
    case .basicExpr:
      return BasicExprSyntax(root: root, data: data)
    case .applicationExprList:
      return ApplicationExprListSyntax(root: root, data: data)
    case .bindingList:
      return BindingListSyntax(root: root, data: data)
    case .binding:
      return BindingSyntax(root: root, data: data)
    case .namedBinding:
      return NamedBindingSyntax(root: root, data: data)
    case .typedBinding:
      return TypedBindingSyntax(root: root, data: data)
    case .basicExprList:
      return BasicExprListSyntax(root: root, data: data)
    case .namedBasicExpr:
      return NamedBasicExprSyntax(root: root, data: data)
    case .underscoreExpr:
      return UnderscoreExprSyntax(root: root, data: data)
    case .typeBasicExpr:
      return TypeBasicExprSyntax(root: root, data: data)
    case .parenthesizedExpr:
      return ParenthesizedExprSyntax(root: root, data: data)
    case .recordExpr:
      return RecordExprSyntax(root: root, data: data)
    }
  }
}
