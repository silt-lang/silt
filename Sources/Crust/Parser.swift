/// Parser.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Lithosphere

enum ParseError: Error {
  case unexpectedToken(TokenSyntax)
  case unexpectedEOF
  case failedParsingExpr
  case failedParsingName
  case failedParsingAscription
  case failedParsingApplication
  case failedParsingBindingList
  case failedParsingFunctionClause
  case failedParsingFunctionClausePattern
  case allDisjunctsFailed
}

public class Parser {
  let tokens: [TokenSyntax]
  var index = 0

  public init(tokens: [TokenSyntax]) {
    self.tokens = tokens
  }

  var currentToken: TokenSyntax? {
    return index < tokens.count ? tokens[index] : nil
  }

  func consume(_ kinds: TokenKind...) throws -> TokenSyntax {
    guard let token = currentToken else {
      throw ParseError.unexpectedEOF
    }
    guard kinds.index(of: token.tokenKind) != nil else {
      throw ParseError.unexpectedToken(token)
    }
    advance()
    return token
  }

  func peek(ahead n: Int = 0) -> TokenKind {
    guard index + n < tokens.count else { return .eof }
    return tokens[index + n].tokenKind
  }

  func advance(_ n: Int = 1) {
    index += n
  }

  func split<T>(_ fs : (() throws -> T)...) throws -> T {
    for f in fs {
      let previousPosition = self.index
      guard let syntax = try? f() else {
        self.index = previousPosition
        continue
      }
      return syntax
    }
    throw ParseError.allDisjunctsFailed
  }
}

extension Parser {
  public func parseTopLevelModule() -> ModuleDeclSyntax? {
    let module = try? parseModule()
    guard let _ = try? consume(.eof) else {
      return nil
    }
    return module
  }
}

extension Parser {
  func parseIdentifierToken() throws -> TokenSyntax {
    guard case .identifier(_) = self.peek() else {
      throw ParseError.unexpectedToken(self.currentToken!)
    }

    let name = self.currentToken!
    self.advance()
    return name
  }

  func parseQualifiedName() throws -> QualifiedNameSyntax {
    var pieces = [QualifiedNamePieceSyntax]()
    while let piece = try? parseQualifiedNamePiece() {
      pieces.append(piece)
    }

    // No pieces, no qualified name.
    guard !pieces.isEmpty else {
      throw ParseError.failedParsingName
    }

    // All the pieces except the last one should have a dot present.
    guard pieces.dropLast().reduce(true, { (acc, p) in
      return acc && p.trailingPeriod != nil
    }) else {
      throw ParseError.failedParsingName
    }

    return QualifiedNameSyntax(elements: pieces)
  }

  func parseQualifiedNamePiece() throws -> QualifiedNamePieceSyntax {
    let name = try parseIdentifierToken()
    let period = (peek() == .period) ? try consume(.period) : nil
    return QualifiedNamePieceSyntax(name: name, trailingPeriod: period)
  }

  func parseIdentifierList() throws -> IdentifierListSyntax {
    var pieces = [TokenSyntax]()
    while let piece = try? parseQualifiedNamePiece() {
      pieces.append(piece.name)
    }
    return IdentifierListSyntax(elements: pieces)
  }
}

extension Parser {
  func parseDeclList() -> DeclListSyntax {
    var pieces = [DeclSyntax]()
    while let piece = try? parseDecl() {
      pieces.append(piece)
    }
    return DeclListSyntax(elements: pieces)
  }

  func parseDecl() throws -> DeclSyntax {
    switch peek() {
    case .moduleKeyword:
      return try self.parseModule()
    case .dataKeyword:
      return try self.parseDataDeclaration()
    case .openKeyword:
      return try self.parseOpenImportDecl()
    case .importKeyword:
      return try self.parseImportDecl()
    default:
      return try self.parseFunctionDecl()
    }
  }

  func parseModule() throws -> ModuleDeclSyntax {
    let moduleKw = try consume(.moduleKeyword)
    let moduleId = try parseQualifiedName()
    let paramList = parseTypedParameterList()
    let whereKw = try consume(.whereKeyword)
    let leftBrace = try consume(.leftBrace)
    let declList = parseDeclList()
    let rightBrace = try consume(.rightBrace)
    return ModuleDeclSyntax(
      moduleToken: moduleKw,
      moduleIdentifier: moduleId,
      typedParameterList: paramList,
      whereToken: whereKw,
      leftBraceToken: leftBrace,
      declList: declList,
      rightBraceToken: rightBrace
    )
  }

  func parseOpenImportDecl() throws -> OpenImportDeclSyntax {
    let openTok = try consume(.openKeyword)
    let importTok = try consume(.importKeyword)
    let ident = try parseQualifiedName()
    return OpenImportDeclSyntax(
      openToken: openTok,
      importToken: importTok,
      importIdentifier: ident
    )
  }

  func parseImportDecl() throws -> ImportDeclSyntax {
    let importTok = try consume(.importKeyword)
    let ident = try parseQualifiedName()
    return ImportDeclSyntax(importToken: importTok, importIdentifier: ident)
  }
}

extension Parser {
  func parseRecordDecl() throws -> RecordDeclSyntax {
    let recordTok = try consume(.recordKeyword)
    let recName = try parseIdentifierToken()
    let paramList = parseTypedParameterList()
    let indices = try? parseTypeIndices()
    let whereTok = try consume(.whereKeyword)
    let elemList = parseRecordElementList()
    return RecordDeclSyntax(
      recordToken: recordTok,
      recordName: recName,
      parameterList: paramList,
      typeIndices: indices,
      whereToken: whereTok,
      recordElementList: elemList
    )
  }

  func parseRecordElementList() -> RecordElementListSyntax {
    var pieces = [DeclSyntax]()
    while let piece = try? parseRecordElement() {
      pieces.append(piece)
    }
    return RecordElementListSyntax(elements: pieces)
  }

  func parseRecordElement() throws -> DeclSyntax {
    return try self.split({
      return try self.parseFieldDecl()
    }, {
      return try self.parseFunctionDecl()
    })
  }

  func parseFieldDecl() throws -> FieldDeclSyntax {
    let fieldTok = try consume(.fieldKeyword)
    let leftTok = try consume(.leftBrace)
    let ascription = try parseAscription()
    let rightTok = try consume(.rightBrace)
    return FieldDeclSyntax(
      fieldToken: fieldTok,
      leftBraceToken: leftTok,
      ascription: ascription,
      rightBraceToken: rightTok
    )
  }
}

extension Parser {
  func parseTypedParameterList() -> TypedParameterListSyntax {
    var pieces = [TypedParameterSyntax]()
    while let piece = try? parseTypedParameter() {
      pieces.append(piece)
    }
    return TypedParameterListSyntax(elements: pieces)
  }

  func parseTypedParameter() throws -> TypedParameterSyntax {
    let leftParen = try consume(.leftParen)
    let ascription = try parseAscription()
    let rightParen = try consume(.rightParen)
    return TypedParameterSyntax(
      leftParenToken: leftParen,
      ascription: ascription,
      rightParenToken: rightParen
    )
  }

  func parseTypeIndices() throws -> TypeIndicesSyntax {
    let colon = try consume(.colon)
    let expr = try parseExpr()
    return TypeIndicesSyntax(colonToken: colon, indexExpr: expr)
  }

  func parseAscription() throws -> AscriptionSyntax {
    let boundNames = try parseIdentifierList()
    let colonToken = try consume(.colon)
    let expr = try parseExpr()
    return AscriptionSyntax(
      boundNames: boundNames,
      colonToken: colonToken,
      typeExpr: expr
    )
  }
}

extension Parser {
  func parseDataDeclaration() throws -> DataDeclSyntax {
    do {
      let dataTok = try consume(.dataKeyword)
      let dataId = try parseQualifiedNamePiece()
      let paramList = parseTypedParameterList()
      let indices = try parseTypeIndices()
      let whereTok = try consume(.whereKeyword)
      let constrList = parseConstructorList()
      return DataDeclSyntax(
        dataToken: dataTok,
        dataIdentifier: dataId.name,
        typedParameterList: paramList,
        typeIndices: indices,
        whereToken: whereTok,
        constructorList: constrList
      )
    } catch let e {
      throw e
    }
  }

  func parseConstructorList() -> ConstructorListSyntax {
    var pieces = [ConstructorDeclSyntax]()
    while let piece = try? parseConstructor() {
      pieces.append(piece)
    }
    return ConstructorListSyntax(elements: pieces)
  }

  func parseConstructor() throws -> ConstructorDeclSyntax {
    let pipe = try consume(.pipe)
    let ascription = try parseAscription()
    return ConstructorDeclSyntax(pipeToken: pipe, ascription: ascription)
  }
}

extension Parser {
  func parseFunctionDecl() throws -> FunctionDeclSyntax {
    let ascription = try parseAscription()
    let ascSemicolon = try consume(.semicolon)
    let clauses = try parseFunctionClauseList()
    let clausesSemiColon = try consume(.semicolon)
    return FunctionDeclSyntax(
      ascription: ascription,
      ascriptionSemicolon: ascSemicolon,
      clauseList: clauses,
      trailingSemicolon: clausesSemiColon
    )
  }

  func parseFunctionClauseList() throws -> FunctionClauseListSyntax {
    var pieces = [FunctionClauseSyntax]()
    while let piece = try? parseFunctionClause() {
      pieces.append(piece)
    }

    guard !pieces.isEmpty else {
      throw ParseError.failedParsingFunctionClause
    }
    return FunctionClauseListSyntax(elements: pieces)
  }

  func parseFunctionClause() throws -> FunctionClauseSyntax {
    return try split({
      return try self.parseWithRuleFunctionClause()
    }, {
      return try self.parseNormalFunctionClause()
    })
  }

  func parseWithRuleFunctionClause() throws -> WithRuleFunctionClauseSyntax {
    let functionName = try parseIdentifierToken()
    let patternClauseList = try parsePatternClauseList()
    let withToken = try consume(.withKeyword)
    let withExpr = try parseExpr()
    let withPatClause = try parsePatternClauseList()
    let equalsTok = try consume(.equals)
    let rhsExpr = try parseExpr()
    return WithRuleFunctionClauseSyntax(
      functionName: functionName,
      patternClauseList: patternClauseList,
      withToken: withToken,
      withExpr: withExpr,
      withPatternClause: withPatClause,
      equalsToken: equalsTok,
      rhsExpr: rhsExpr
    )
  }

  func parseNormalFunctionClause() throws -> NormalFunctionClauseSyntax {
    let functionName = try parseIdentifierToken()
    let patternClauseList = try parsePatternClauseList()
    let equalsTok = try consume(.equals)
    let rhsExpr = try parseExpr()
    return NormalFunctionClauseSyntax(
      functionName: functionName,
      patternClauseList: patternClauseList,
      equalsToken: equalsTok,
      rhsExpr: rhsExpr
    )
  }
}

extension Parser {
  func parsePatternClauseList() throws -> PatternClauseListSyntax {
    var pieces = [ExprSyntax]()
    while let piece = try? parseExpr() {
      pieces.append(piece)
    }

    guard !pieces.isEmpty else {
      throw ParseError.failedParsingFunctionClausePattern
    }

    return PatternClauseListSyntax(elements: pieces)
  }
}

extension Parser {
  func parseExpr() throws -> ExprSyntax {
    if let expr = try? split({
      return try self.parseTypedParameterArrowExpr()
    }, {
      return try self.parseBasicExprListArrowExprSyntax()
    }) {
      return expr
    }

    switch peek() {
    case .forwardSlash:
      return try self.parseLambdaExpr()
    case .forallSymbol, .forallKeyword:
      return try self.parseQuantifiedExpr()
    case .letKeyword:
      return try self.parseLetExpr()
    default:
      return try split({
        return try self.parseApplicationExpr()
      }, {
        return try self.parseBasicExpr()
      })
    }
  }

  func parseTypedParameterArrowExpr() throws -> TypedParameterArrowExprSyntax {
    let parameter = try parseTypedParameter()
    let arrow = try consume(.arrow)
    let outputExpr = try parseExpr()
    return TypedParameterArrowExprSyntax(
      parameter: parameter,
      arrowToken: arrow,
      outputExpr: outputExpr
    )
  }

  func parseBasicExprListArrowExprSyntax() throws -> BasicExprListArrowExprSyntax {
    let exprList = try parseBasicExprList()
    let arrow = try consume(.arrow)
    let outputExpr = try parseExpr()
    return BasicExprListArrowExprSyntax(
      exprList: exprList,
      arrowToken: arrow,
      outputExpr: outputExpr
    )
  }

  func parseLambdaExpr() throws -> LambdaExprSyntax {
    let slashTok = try consume(.forwardSlash)
    let bindingList = try parseBindingList()
    let bodyExpr = try parseExpr()
    return LambdaExprSyntax(
      slashToken: slashTok,
      bindingList: bindingList,
      bodyExpr: bodyExpr
    )
  }

  func parseQuantifiedExpr() throws -> QuantifiedExprSyntax {
    let forallTok = try consume(.forallSymbol, .forallKeyword)
    let bindingList = parseTypedParameterList()
    let arrow = try consume(.arrow)
    let outputExpr = try parseExpr()
    return QuantifiedExprSyntax(
      forallToken: forallTok,
      bindingList: bindingList,
      arrowToken: arrow,
      outputExpr: outputExpr
    )
  }

  func parseLetExpr() throws -> LetExprSyntax {
    let letTok = try consume(.letKeyword)
    let declList = parseDeclList()
    let inTok = try consume(.inKeyword)
    let outputExpr = try parseExpr()
    return LetExprSyntax(
      letToken: letTok,
      declList: declList,
      inToken: inTok,
      outputExpr: outputExpr
    )
  }

  func parseApplicationExpr() throws -> ApplicationExprSyntax {
    let appExprList = try parseApplicationExprList()
    return ApplicationExprSyntax(exprs: appExprList)
  }

  func parseApplicationExprList() throws -> ApplicationExprListSyntax {
    var pieces = [BasicExprSyntax]()
    while let piece = try? parseBasicExpr() {
      pieces.append(piece)
    }
    guard pieces.count >= 2 else {
      throw ParseError.failedParsingApplication
    }
    return ApplicationExprListSyntax(elements: pieces)
  }

  func parseBasicExprList() throws -> BasicExprListSyntax {
    var pieces = [BasicExprSyntax]()
    while let piece = try? parseBasicExpr() {
      pieces.append(piece)
    }

    guard !pieces.isEmpty else {
      throw ParseError.failedParsingExpr
    }

    return BasicExprListSyntax(elements: pieces)
  }

  func parseBasicExpr() throws -> BasicExprSyntax {
    switch peek() {
    case .underscore:
      return try self.parseUnderscoreExpr()
    case .typeKeyword:
      return try self.parseTypeBasicExpr()
    case .leftBrace:
      return try self.parseParenthesizedExpr()
    case .recordKeyword:
      return try self.parseRecordExpr()
    default:
      return try self.parseNamedBasicExpr()
    }
  }

  func parseRecordExpr() throws -> RecordExprSyntax {
    let recordTok = try consume(.recordKeyword)
    let parameterExpr = try? parseBasicExpr()
    let leftBrace = try consume(.leftBrace)
    let fieldAssigns = parseRecordFieldAssignmentList()
    let rightBrace = try consume(.rightBrace)
    return RecordExprSyntax(
      recordToken: recordTok,
      parameterExpr: parameterExpr,
      leftBraceToken: leftBrace,
      fieldAssignments: fieldAssigns,
      rightBraceToken: rightBrace
    )
  }

  func parseRecordFieldAssignmentList() -> RecordFieldAssignmentListSyntax {
    var pieces = [RecordFieldAssignmentSyntax]()
    while let piece = try? parseRecordFieldAssignment() {
      pieces.append(piece)
    }

    return RecordFieldAssignmentListSyntax(elements: pieces)
  }

  func parseRecordFieldAssignment() throws -> RecordFieldAssignmentSyntax {
    let fieldName = try parseIdentifierToken()
    let equalsTok = try consume(.equals)
    let fieldInit = try parseExpr()
    let trailingSemi = try? consume(.semicolon)
    return RecordFieldAssignmentSyntax(
      fieldName: fieldName,
      equalsToken: equalsTok,
      fieldInitExpr: fieldInit,
      trailingSemicolon: trailingSemi
    )
  }

  func parseNamedBasicExpr() throws -> NamedBasicExprSyntax {
    let name = try parseQualifiedName()
    return NamedBasicExprSyntax(name: name)
  }

  func parseUnderscoreExpr() throws -> UnderscoreExprSyntax {
    let underscore = try consume(.underscore)
    return UnderscoreExprSyntax(underscoreToken: underscore)
  }

  func parseTypeBasicExpr() throws -> TypeBasicExprSyntax {
    let typeTok = try consume(.typeKeyword)
    return TypeBasicExprSyntax(typeToken: typeTok)
  }

  func parseParenthesizedExpr() throws -> ParenthesizedExprSyntax {
    let leftParen = try consume(.leftParen)
    let expr = try parseExpr()
    let rightParen = try consume(.rightParen)
    return ParenthesizedExprSyntax(
      leftParenToken: leftParen,
      expr: expr,
      rightParenToken: rightParen
    )
  }

  func parseBindingList() throws -> BindingListSyntax {
    var pieces = [BindingSyntax]()
    while let piece = try? parseBinding() {
      pieces.append(piece)
    }

    guard !pieces.isEmpty else {
      throw ParseError.failedParsingBindingList
    }

    return BindingListSyntax(elements: pieces)
  }

  func parseBinding() throws -> BindingSyntax {
    return try split({
      return try self.parseNamedBinding()
    }, {
      return try self.parseTypedBinding()
    })
  }

  func parseNamedBinding() throws -> NamedBindingSyntax {
    let name = try parseQualifiedName()
    return NamedBindingSyntax(name: name)
  }

  func parseTypedBinding() throws -> TypedBindingSyntax {
    let parameter = try parseTypedParameter()
    return TypedBindingSyntax(parameter: parameter)
  }
}
