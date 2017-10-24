/// Parser.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Lithosphere

extension Diagnostic.Message {
  static func unexpectedToken(
    _ token: TokenSyntax, expected: TokenKind? = nil) -> Diagnostic.Message {
    var msg: String
    switch token.tokenKind {
    case .leftBrace where token.isImplicit:
      msg = "unexpected opening scope"
    case .rightBrace where token.isImplicit:
      msg = "unexpected end of scope"
    case .semicolon where token.isImplicit:
      msg = "unexpected end of line"
    default:
      msg = "unexpected token '\(token.tokenKind.text)'"
    }
    if let kind = expected {
      msg += " (expected '\(kind.text)')"
    }
    return .init(.error, msg)
  }
  static let unexpectedEOF =
    Diagnostic.Message(.error, "unexpected end-of-file reached")
  static func expected(_ name: String) -> Diagnostic.Message {
    return Diagnostic.Message(.error, "expected \(name)")
  }
}

public class Parser {
  let engine: DiagnosticEngine
  let tokens: [TokenSyntax]
  var index = 0

  public init(diagnosticEngine: DiagnosticEngine, tokens: [TokenSyntax]) {
    self.engine = diagnosticEngine
    self.tokens = tokens
  }

  var currentToken: TokenSyntax? {
    return index < tokens.count ? tokens[index] : nil
  }

  /// Looks backwards from where we are in the token stream for
  /// the first non-implicit token to which we can attach a diagnostic.
  func previousNonImplicitToken() -> TokenSyntax? {
    var i = 0
    while let tok = peekToken(ahead: i) {
      defer { i -= 1 }
      if tok.isImplicit { continue }
      return tok
    }
    return nil
  }

  func unexpectedToken(expected: TokenKind? = nil) -> Diagnostic.Message {
    // If we've "unexpected" an implicit token from Shining, highlight
    // instead the previous token because the diagnostic will say that we've
    // begun or ended the scope/line.
    let highlightedToken = previousNonImplicitToken()
    guard let token = currentToken else {
      return engine.diagnose(.unexpectedEOF, node: highlightedToken)
    }
    return engine.diagnose(.unexpectedToken(token, expected: expected),
                           node: highlightedToken) {
      if let tok = highlightedToken {
        $0.highlight(tok)
      }
    }
  }

  func consume(_ kinds: TokenKind...) throws -> TokenSyntax {
    guard let token = currentToken, kinds.contains(token.tokenKind) else {
      throw unexpectedToken(expected: kinds.first)
    }
    advance()
    return token
  }

  func peek(ahead n: Int = 0) -> TokenKind {
    return peekToken(ahead: n)?.tokenKind ?? .eof
  }

  func peekToken(ahead n: Int = 0) -> TokenSyntax? {
    guard index + n < tokens.count else { return nil }
    return tokens[index + n]
  }

  func advance(_ n: Int = 1) {
    index += n
  }
}

extension Parser {
  public func parseTopLevelModule() -> ModuleDeclSyntax? {
    do {
      let module = try parseModule()
      _ = try consume(.eof)
      return module
    } catch {
      return nil
    }
  }
}

extension Parser {
  func parseIdentifierToken() throws -> TokenSyntax {
    guard case .identifier(_) = peek() else {
      throw unexpectedToken()
    }

    let name = currentToken!
    advance()
    return name
  }

  func parseQualifiedName() throws -> QualifiedNameSyntax {
    var pieces = [QualifiedNamePieceSyntax]()
    while true {
      guard case .identifier(_) = peek() else { continue }
      let id = try parseIdentifierToken()
      if case .period = peek() {
        let period = try consume(.period)
        pieces.append(QualifiedNamePieceSyntax(name: id,
                                               trailingPeriod: period))
      } else {
        pieces.append(QualifiedNamePieceSyntax(name: id,
                                               trailingPeriod: nil))
        break
      }
    }

    // No pieces, no qualified name.
    guard !pieces.isEmpty else {
      throw engine.diagnose(.expected("name"), node: currentToken)
    }

    return QualifiedNameSyntax(elements: pieces)
  }

  func parseIdentifierList() -> IdentifierListSyntax {
    var pieces = [TokenSyntax]()
    loop: while true {
      switch peek() {
      case .identifier(_), .underscore:
        pieces.append(currentToken!)
        advance()
      default: break loop
      }
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
    let paramList = try parseTypedParameterList()
    let whereKw = try consume(.whereKeyword)
    let leftBrace = try consume(.leftBrace)
    let declList = parseDeclList()
    let rightBrace = try consume(.rightBrace)
    let semi = try consume(.semicolon)
    return ModuleDeclSyntax(
      moduleToken: moduleKw,
      moduleIdentifier: moduleId,
      typedParameterList: paramList,
      whereToken: whereKw,
      leftBraceToken: leftBrace,
      declList: declList,
      rightBraceToken: rightBrace,
      trailingSemicolon: semi
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
    let paramList = try parseTypedParameterList()
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
    switch peek() {
    case .fieldKeyword:
      return try self.parseFieldDecl()
    default:
      return try self.parseFunctionDecl()
    }
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
  func isStartOfTypedParameter() -> Bool {
    return [.leftParen, .leftBrace].contains(peek())
  }

  func parseTypedParameterList() throws -> TypedParameterListSyntax {
    var pieces = [TypedParameterSyntax]()
    while isStartOfTypedParameter() {
      pieces.append(try parseTypedParameter())
    }
    return TypedParameterListSyntax(elements: pieces)
  }

  func parseTypedParameter() throws -> TypedParameterSyntax {
    switch peek() {
    case .leftParen:
      return try self.parseExplicitTypedParameter()
    case .leftBrace:
      return try self.parseImplicitTypedParameter()
    default:
      throw unexpectedToken()
    }
  }

  func parseExplicitTypedParameter() throws -> ExplicitTypedParameterSyntax {
    let leftParen = try consume(.leftParen)
    let ascription = try parseAscription()
    let rightParen = try consume(.rightParen)
    return ExplicitTypedParameterSyntax(
      leftParenToken: leftParen,
      ascription: ascription,
      rightParenToken: rightParen)
  }

  func parseImplicitTypedParameter() throws -> ImplicitTypedParameterSyntax {
    let leftBrace = try consume(.leftBrace)
    let ascription = try parseAscription()
    let rightBrace = try consume(.rightBrace)
    return ImplicitTypedParameterSyntax(
      leftBraceToken: leftBrace,
      ascription: ascription,
      rightBraceToken: rightBrace)
  }

  func parseTypeIndices() throws -> TypeIndicesSyntax {
    let colon = try consume(.colon)
    let expr = try parseExpr()
    return TypeIndicesSyntax(colonToken: colon, indexExpr: expr)
  }

  func parseAscription() throws -> AscriptionSyntax {
    let boundNames = parseIdentifierList()
    let colonToken = try consume(.colon)
    let expr = try parseExpr()
    return AscriptionSyntax(
      boundNames: boundNames,
      colonToken: colonToken,
      typeExpr: expr)
  }
}

extension Parser {
  func parseDataDeclaration() throws -> DataDeclSyntax {
    let dataTok = try consume(.dataKeyword)
    let dataId = try parseIdentifierToken()
    let paramList = try parseTypedParameterList()
    let indices = try parseTypeIndices()
    let whereTok = try consume(.whereKeyword)
    let leftBrace = try consume(.leftBrace)
    let constrList = parseConstructorList()
    let rightBrace = try consume(.rightBrace)
    let semi = try consume(.semicolon)
    return DataDeclSyntax(
      dataToken: dataTok,
      dataIdentifier: dataId,
      typedParameterList: paramList,
      typeIndices: indices,
      whereToken: whereTok,
      leftBraceToken: rightBrace,
      constructorList: constrList,
      rightBraceToken: leftBrace,
      trailingSemicolon: semi)
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
    let semi = try consume(.semicolon)
    return ConstructorDeclSyntax(
      pipeToken: pipe,
      ascription: ascription,
      trailingSemicolon: semi)
  }
}

extension Parser {
  func parseFunctionDecl() throws -> FunctionDeclSyntax {
    let ascription = try parseAscription()
    let ascSemicolon = try consume(.semicolon)
    let clauses = try parseFunctionClauseList()
    return FunctionDeclSyntax(
      ascription: ascription,
      ascriptionSemicolon: ascSemicolon,
      clauseList: clauses)
  }

  func parseFunctionClauseList() throws -> FunctionClauseListSyntax {
    var pieces = [FunctionClauseSyntax]()
    while let piece = try? parseFunctionClause() {
      pieces.append(piece)
    }

    guard !pieces.isEmpty else {
      throw engine.diagnose(.expected("function clause"), node: currentToken)
    }
    return FunctionClauseListSyntax(elements: pieces)
  }

  func parseFunctionClause() throws -> FunctionClauseSyntax {
    let functionName = try parseIdentifierToken()
    let patternClauseList = try parsePatternClauseList()
    if case .withKeyword = peek() {
      return WithRuleFunctionClauseSyntax(
        functionName: functionName,
        patternClauseList: patternClauseList,
        withToken: try consume(.withKeyword),
        withExpr: try parseExpr(),
        withPatternClause: try parsePatternClauseList(),
        equalsToken: try consume(.equals),
        rhsExpr: try parseExpr(),
        trailingSemicolon: try consume(.semicolon))
    }
    return NormalFunctionClauseSyntax(
      functionName: functionName,
      patternClauseList: patternClauseList,
      equalsToken: try consume(.equals),
      rhsExpr: try parseExpr(),
      trailingSemicolon: try consume(.semicolon))
  }
}

extension Parser {
  func parsePatternClauseList() throws -> PatternClauseListSyntax {
    var pieces = [ExprSyntax]()
    while let piece = try? parseExpr() {
      pieces.append(piece)
    }

    guard !pieces.isEmpty else {
      throw engine.diagnose(.expected("function clause pattern"),
                            node: currentToken)
    }

    return PatternClauseListSyntax(elements: pieces)
  }
}

extension Parser {
  func isStartOfBasicExpr() -> Bool {
    switch peek() {
    case .underscore, .typeKeyword, .leftParen, .recordKeyword, .identifier(_):
      return true
    default:
      return false
    }
  }

  func parseExpr() throws -> ExprSyntax {
    if isStartOfTypedParameter() {
      return try self.parseTypedParameterArrowExpr()
    }

    //FIXME: re-enable: return try self.parseBasicExprListArrowExprSyntax()

    switch peek() {
    case .forwardSlash:
      return try self.parseLambdaExpr()
    case .forallSymbol, .forallKeyword:
      return try self.parseQuantifiedExpr()
    case .letKeyword:
      return try self.parseLetExpr()
    default:
      /// Function applications are one or more expressions in a row.
      let basic = try self.parseBasicExpr()
      if isStartOfBasicExpr() {
        var exprs = try parseBasicExprs()
        exprs.insert(basic, at: 0)
        let exprList = BasicExprListSyntax(elements: exprs)
        if case .arrow = peek() {
          let arrowToken = try consume(.arrow)
          let outputExpr = try parseExpr()
          return BasicExprListArrowExprSyntax(
            exprList: exprList,
            arrowToken: arrowToken,
            outputExpr: outputExpr)
        } else {
          return ApplicationExprSyntax(exprs: exprList)
        }
      }
      return basic
    }
  }

  func parseTypedParameterArrowExpr() throws -> TypedParameterArrowExprSyntax {
    let parameters = try parseTypedParameterList()
    guard !parameters.isEmpty else {
      throw engine.diagnose(.expected("type ascription"), node: currentToken)
    }
    let arrow = try consume(.arrow)
    let outputExpr = try parseExpr()
    return TypedParameterArrowExprSyntax(
      parameters: parameters,
      arrowToken: arrow,
      outputExpr: outputExpr
    )
  }

<<<<<<< HEAD
<<<<<<< HEAD
  func parseBasicExprListArrowExpr() throws -> BasicExprListArrowExprSyntax {
=======
  func parseBasicExprListArrowExprSyntax() throws
    -> BasicExprListArrowExprSyntax {
>>>>>>> Begin removing backtracking from parser and adding diagnostics
    let exprList = try parseBasicExprList()
    let arrow = try consume(.arrow)
    let outputExpr = try parseExpr()
    return BasicExprListArrowExprSyntax(
      exprList: exprList,
      arrowToken: arrow,
      outputExpr: outputExpr
    )
  }

=======
>>>>>>> Got parser building again and improved handling of implicit tokens in diagnostics.
  func parseLambdaExpr() throws -> LambdaExprSyntax {
    let slashTok = try consume(.forwardSlash)
    let bindingList = try parseBindingList()
    let arrowTok = try consume(.arrow)
    let bodyExpr = try parseExpr()
    return LambdaExprSyntax(
      slashToken: slashTok,
      bindingList: bindingList,
      arrowToken: arrowTok,
      bodyExpr: bodyExpr
    )
  }

  func parseQuantifiedExpr() throws -> QuantifiedExprSyntax {
    let forallTok = try consume(.forallSymbol, .forallKeyword)
    let bindingList = try parseTypedParameterList()
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
      outputExpr: outputExpr)
  }

  func parseBasicExprs(
    diagType: String = "expression") throws -> [BasicExprSyntax] {
    var pieces = [BasicExprSyntax]()
    while let piece = try? parseBasicExpr() {
      pieces.append(piece)
    }

    guard !pieces.isEmpty else {
      throw engine.diagnose(.expected(diagType), node: currentToken)
    }
    return pieces
  }

  func parseBasicExprList(
    diagType: String = "expression") throws -> BasicExprListSyntax {
    return BasicExprListSyntax(elements:
      try parseBasicExprs(diagType: diagType))
  }

  func parseBasicExpr() throws -> BasicExprSyntax {
    switch peek() {
    case .underscore:
      return try self.parseUnderscoreExpr()
    case .typeKeyword:
      return try self.parseTypeBasicExpr()
    case .leftParen:
      return try self.parseParenthesizedExpr()
    case .recordKeyword:
      return try self.parseRecordExpr()
    case .identifier(_):
      return try self.parseNamedBasicExpr()
    default:
      throw engine.diagnose(.expected("expression"), node: currentToken)
    }
  }

  func parseRecordExpr() throws -> RecordExprSyntax {
    let recordTok = try consume(.recordKeyword)
    let parameterExpr = isStartOfBasicExpr() ? try parseBasicExpr() : nil
    let leftBrace = try consume(.leftBrace)
    let fieldAssigns = try parseRecordFieldAssignmentList()
    let rightBrace = try consume(.rightBrace)
    return RecordExprSyntax(
      recordToken: recordTok,
      parameterExpr: parameterExpr,
      leftBraceToken: leftBrace,
      fieldAssignments: fieldAssigns,
      rightBraceToken: rightBrace
    )
  }

  func parseRecordFieldAssignmentList() throws
    -> RecordFieldAssignmentListSyntax {
    var pieces = [RecordFieldAssignmentSyntax]()
    while case .identifier(_) = peek() {
      pieces.append(try parseRecordFieldAssignment())
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
      throw engine.diagnose(.expected("binding list"), node: currentToken)
    }

    return BindingListSyntax(elements: pieces)
  }

  func parseBinding() throws -> BindingSyntax {
    if isStartOfTypedParameter() {
      return try parseTypedBinding()
    }
    return try parseNamedBinding()
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
