/// Parser.swift
///
/// Copyright 2017-2018, The Silt Language Project.
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

  static let expectedTopLevelModule =
    Diagnostic.Message(
      .error, "missing required top level module")

  static let expectedNameInFuncDecl =
    Diagnostic.Message(
      .error, "expression may not be used as identifier in function name")

  static func unexpectedQualifiedName(
    _ syntax: QualifiedNameSyntax) -> Diagnostic.Message {
    let txt = syntax.triviaFreeSourceText
    return Diagnostic.Message(
      .error,
      "qualified name '\(txt)' is not allowed in this position")
  }

  static let unexpectedConstructor =
    Diagnostic.Message(.error,
                       """
                       data constructors may only appear within the scope of a \
                       data declaration
                       """)

  static let emptyDataDeclWithWhere =
    Diagnostic.Message(.error,
                       """
                       data declaration with no constructors cannot have a \
                       'where' clause
                       """)

  static let indentToMakeConstructor =
    Diagnostic.Message(.note, """
                              indent this declaration to make it a constructor
                              """)

  static let removeWhereClause =
    Diagnostic.Message(.note, """
                              remove 'where' to make an empty data declaration
                              """)
}

public class Parser {
  let engine: DiagnosticEngine
  let tokens: [TokenSyntax]
  public var index = 0

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

  func expected(_ name: String) -> Diagnostic.Message {
    let highlightedToken = previousNonImplicitToken()
    return engine.diagnose(.expected(name), node: highlightedToken) {
      if let tok = highlightedToken {
        $0.highlight(tok)
      }
    }
  }

  func unexpectedToken(expected: TokenKind? = nil) -> Diagnostic.Message {
    // If we've "unexpected" an implicit token from Shining, highlight
    // instead the previous token because the diagnostic will say that we've
    // begun or ended the scope/line.
    let highlightedToken = previousNonImplicitToken()
    guard let token = currentToken else {
      return engine.diagnose(.unexpectedEOF, node: highlightedToken)
    }
    let msg = Diagnostic.Message.unexpectedToken(token, expected: expected)
    return engine.diagnose(msg, node: highlightedToken) {
      if let tok = highlightedToken {
        $0.highlight(tok)
      }
    }
  }

  func consumeIf(_ kinds: TokenKind...) throws -> TokenSyntax? {
    guard let token = currentToken else {
      throw unexpectedToken(expected: kinds.first)
    }
    if kinds.contains(token.tokenKind) {
      advance()
      return token
    }
    return nil
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

  public func advance(_ n: Int = 1) {
    index += n
  }
}

extension Parser {
  public func parseTopLevelModule() -> ModuleDeclSyntax? {
    do {
      guard peek() == .moduleKeyword else {
        throw engine.diagnose(.expectedTopLevelModule, node: currentToken)
      }
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
      throw expected("name")
    }

    return QualifiedNameSyntax(elements: pieces)
  }

  /// Ensures all of the QualifiedNameSyntax nodes passed in are basic names,
  /// not actually fully qualified names.
  func ensureAllNamesSimple(_ names: [QualifiedNameSyntax]) -> [TokenSyntax] {
    return names.map { qn -> TokenSyntax in
      let name = qn.first!
      if name.trailingPeriod != nil || qn.count != 1 {
        // Diagnose the qualified name and recover by using just the
        // first piece.
        engine.diagnose(.unexpectedQualifiedName(qn), node: qn) {
          $0.highlight(qn)
        }
      }
      return name.name
    }
  }

  func parseIdentifierList() throws -> IdentifierListSyntax {
    var names = [QualifiedNameSyntax]()
    loop: while true {
      switch peek() {
      case .identifier(_), .underscore:
        // Parse qualified names, then verify they are all identifiers.
        names.append(try parseQualifiedName())
      default: break loop
      }
    }
    return IdentifierListSyntax(elements: ensureAllNamesSimple(names))
  }
}

extension Parser {
  func parseDeclList() throws -> DeclListSyntax {
    var pieces = [DeclSyntax]()
    while peek() != .rightBrace {
      // Recover from invalid declarations by ignoring them.
      guard let decl = try? parseDecl() else {
        continue
      }

      // If this is a function declaration directly after an empty data
      // declaration with a `where` clause (which should have caused an error),
      // diagnose this as a possible constructor.
      if decl is FunctionDeclSyntax,
         let lastData = pieces.last as? DataDeclSyntax,
         lastData.constructorList.isEmpty {
        throw engine.diagnose(.unexpectedConstructor, node: decl) {
          $0.highlight(decl)
          $0.note(.indentToMakeConstructor, node: decl)
        }
      }
      pieces.append(decl)
    }
    return DeclListSyntax(elements: pieces)
  }

  func parseDecl() throws -> DeclSyntax {
    switch peek() {
    case .moduleKeyword:
      return try self.parseModule()
    case .dataKeyword:
      let decl = try self.parseDataDecl()

      // If there's a regular data decl and an empty constructor list,
      // throw an error.
      if let dataDecl = decl as? DataDeclSyntax,
        dataDecl.constructorList.isEmpty {
        engine.diagnose(.emptyDataDeclWithWhere, node: decl) {
          $0.highlight(decl)
          $0.note(.removeWhereClause, node: dataDecl.whereToken,
                  highlights: [dataDecl.whereToken])
        }
      }
      return decl
    case .recordKeyword:
      return try self.parseRecordDecl()
    case .openKeyword:
      return try self.parseOpenImportDecl()
    case .importKeyword:
      return try self.parseImportDecl()
    case .infixKeyword, .infixlKeyword, .infixrKeyword:
      return try self.parseInfixDecl()
    case .identifier(_):
      return try self.parseFunctionDeclOrClause()
    default:
      advance()
      throw expected("declaration")
    }
  }

  func parseModule() throws -> ModuleDeclSyntax {
    let moduleKw = try consume(.moduleKeyword)
    let moduleId = try parseQualifiedName()
    let paramList = try parseTypedParameterList()
    let whereKw = try consume(.whereKeyword)
    let leftBrace = try consume(.leftBrace)
    let declList = try parseDeclList()
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
  func parseInfixDecl() throws -> FixityDeclSyntax {
    switch peek() {
    case .infixKeyword:
      return try self.parseNonFixDecl()
    case .infixlKeyword:
      return try self.parseLeftFixDecl()
    case .infixrKeyword:
      return try self.parseRightFixDecl()
    default:
      throw unexpectedToken()
    }
  }

  func parseNonFixDecl() throws -> NonFixDeclSyntax {
    let tok = try consume(.infixKeyword)
    let prec = try parseIdentifierToken()
    let ids = try parseIdentifierList()
    let semi = try consume(.semicolon)
    return NonFixDeclSyntax(
      infixToken: tok,
      precedence: prec,
      names: ids,
      trailingSemicolon: semi
    )
  }

  func parseLeftFixDecl() throws -> LeftFixDeclSyntax {
    let tok = try consume(.infixlKeyword)
    let prec = try parseIdentifierToken()
    let ids = try parseIdentifierList()
    let semi = try consume(.semicolon)
    return LeftFixDeclSyntax(
      infixlToken: tok,
      precedence: prec,
      names: ids,
      trailingSemicolon: semi
    )
  }

  func parseRightFixDecl() throws -> RightFixDeclSyntax {
    let tok = try consume(.infixrKeyword)
    let prec = try parseIdentifierToken()
    let ids = try parseIdentifierList()
    let semi = try consume(.semicolon)
    return RightFixDeclSyntax(
      infixrToken: tok,
      precedence: prec,
      names: ids,
      trailingSemicolon: semi
    )
  }
}

extension Parser {
  func parseRecordDecl() throws -> RecordDeclSyntax {
    let recordTok = try consume(.recordKeyword)
    let recName = try parseIdentifierToken()
    let paramList = try parseTypedParameterList()
    let indices = peek() == .colon ? try parseTypeIndices() : nil
    let whereTok = try consume(.whereKeyword)
    let leftTok = try consume(.leftBrace)
    let elemList = try parseRecordElementList()
    let rightTok = try consume(.rightBrace)
    let trailingSemi = try consume(.semicolon)
    return RecordDeclSyntax(
      recordToken: recordTok,
      recordName: recName,
      parameterList: paramList,
      typeIndices: indices,
      whereToken: whereTok,
      leftParenToken: leftTok,
      recordElementList: elemList,
      rightParenToken: rightTok,
      trailingSemicolon: trailingSemi
    )
  }

  func parseRecordElementList() throws -> DeclListSyntax {
    var pieces = [DeclSyntax]()
    loop: while true {
      switch peek() {
      case .identifier(_):
        pieces.append(try parseFunctionDeclOrClause())
      case .fieldKeyword:
        pieces.append(try parseFieldDecl())
      case .constructorKeyword:
        pieces.append(try parseRecordConstructorDecl())
      default:
        break loop
      }
    }
    return DeclListSyntax(elements: pieces)
  }

  func parseRecordElement() throws -> DeclSyntax {
    switch peek() {
    case .fieldKeyword:
      return try self.parseFieldDecl()
    case .identifier(_):
      return try self.parseFunctionDeclOrClause()
    case .constructorKeyword:
      return try parseRecordConstructorDecl()
    default:
      throw expected("field or function declaration")
    }
  }

  func parseFieldDecl() throws -> FieldDeclSyntax {
    let fieldTok = try consume(.fieldKeyword)
    let ascription = try parseAscription()
    let trailingSemi = try consume(.semicolon)
    return FieldDeclSyntax(
      fieldToken: fieldTok,
      ascription: ascription,
      trailingSemicolon: trailingSemi
    )
  }

  func parseRecordConstructorDecl() throws -> RecordConstructorDeclSyntax {
    let constrTok = try consume(.constructorKeyword)
    let constrName = try parseIdentifierToken()
    let trailingSemi = try consume(.semicolon)
    return RecordConstructorDeclSyntax(
      constructorToken: constrTok,
      constructorName: constrName,
      trailingSemicolon: trailingSemi
    )
  }
}

extension Parser {
  func isStartOfTypedParameter() -> Bool {
    guard self.index + 1 < self.tokens.endIndex else { return false }
    switch (peek(), peek(ahead: 1)) {
    case (.leftBrace, .identifier(_)): return true
    case (.leftParen, .identifier(_)): return true
    default: return false
    }
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
      throw expected("typed parameter")
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
    let boundNames = try parseIdentifierList()
    let colonToken = try consume(.colon)
    let expr = try parseExpr()
    return AscriptionSyntax(
      boundNames: boundNames,
      colonToken: colonToken,
      typeExpr: expr)
  }
}

extension Parser {
  func parseDataDecl() throws -> DeclSyntax {
    let dataTok = try consume(.dataKeyword)
    let dataId = try parseIdentifierToken()
    let paramList = try parseTypedParameterList()
    let indices = try parseTypeIndices()
    if peek() == .whereKeyword {
      let whereTok = try consume(.whereKeyword)
      let leftBrace = try consume(.leftBrace)
      let constrList = try parseConstructorList()
      let rightBrace = try consume(.rightBrace)
      let semi = try consume(.semicolon)
      return DataDeclSyntax(
        dataToken: dataTok,
        dataIdentifier: dataId,
        typedParameterList: paramList,
        typeIndices: indices,
        whereToken: whereTok,
        leftBraceToken: leftBrace,
        constructorList: constrList,
        rightBraceToken: rightBrace,
        trailingSemicolon: semi)
    } else {
      let semi = try consume(.semicolon)
      return EmptyDataDeclSyntax(
        dataToken: dataTok,
        dataIdentifier: dataId,
        typedParameterList: paramList,
        typeIndices: indices,
        trailingSemicolon: semi)
    }
  }

  func parseConstructorList() throws -> ConstructorListSyntax {
    var pieces = [ConstructorDeclSyntax]()
    while peek() != .rightBrace {
      pieces.append(try parseConstructor())
    }
    return ConstructorListSyntax(elements: pieces)
  }

  func parseConstructor() throws -> ConstructorDeclSyntax {
    let ascription = try parseAscription()
    let semi = try consume(.semicolon)
    return ConstructorDeclSyntax(
      ascription: ascription,
      trailingSemicolon: semi)
  }
}

extension Parser {
  func parseFunctionDeclOrClause() throws -> DeclSyntax {

    let exprs = try parseBasicExprList()
    switch peek() {
    case .colon:
      return try self.finishParsingFunctionDecl(exprs)
    case .equals, .withKeyword:
      return try self.finishParsingFunctionClause(exprs)
    default:
      throw expected("colon or equals")
    }
  }

  func finishParsingFunctionDecl(
        _ exprs: BasicExprListSyntax) throws -> FunctionDeclSyntax {
    let colonTok = try self.consume(.colon)
    let boundNames = IdentifierListSyntax(elements: try exprs.map { expr in
      guard let namedExpr = expr as? NamedBasicExprSyntax else {
        throw engine.diagnose(.expectedNameInFuncDecl, node: expr)
      }

      guard let name = namedExpr.name.first, namedExpr.name.count == 1 else {
        throw engine.diagnose(.unexpectedQualifiedName(namedExpr.name),
                              node: namedExpr)
      }
      return name.name
    })
    let typeExpr = try self.parseExpr()
    let ascription = AscriptionSyntax(
      boundNames: boundNames,
      colonToken: colonTok,
      typeExpr: typeExpr
    )
    return FunctionDeclSyntax(
      ascription: ascription,
      trailingSemicolon: try consume(.semicolon))
  }

  func finishParsingFunctionClause(
        _ exprs: BasicExprListSyntax) throws -> FunctionClauseDeclSyntax {
    if case .withKeyword = peek() {
      return WithRuleFunctionClauseDeclSyntax(
        basicExprList: exprs,
        withToken: try consume(.withKeyword),
        withExpr: try parseExpr(),
        withPatternClause: try parseBasicExprList(),
        equalsToken: try consume(.equals),
        rhsExpr: try parseExpr(),
        trailingSemicolon: try consume(.semicolon))
    }
    assert(peek() == .equals)
    return NormalFunctionClauseDeclSyntax(
      basicExprList: exprs,
      equalsToken: try consume(.equals),
      rhsExpr: try parseExpr(),
      trailingSemicolon: try consume(.semicolon))
  }
}

extension Parser {
  func isStartOfExpr() -> Bool {
    if isStartOfBasicExpr() { return true }
    switch peek() {
    case .forwardSlash, .forallSymbol, .forallKeyword, .letKeyword:
      return true
    default:
      return false
    }
  }

  func isStartOfBasicExpr() -> Bool {
    switch peek() {
    case .underscore, .typeKeyword,
         .leftParen, .leftBrace,
         .recordKeyword, .identifier(_):
      return true
    default:
      return false
    }
  }

  // Breaks the ambiguity in parsing the beginning of a typed parameter
  //
  // (a b c ... : <expr>)
  //
  // and the beginning of an application expression
  //
  // (a b c ...)
  func parseParenthesizedExpr() throws -> BasicExprSyntax {
    let leftParen = try consume(.leftParen)
    // If we've hit a non-identifier token, start parsing a parenthesized
    // expression.
    guard case .identifier(_) = peek() else {
      let expr = try parseExpr()
      let rightParen = try consume(.rightParen)
      return ParenthesizedExprSyntax(
        leftParenToken: leftParen,
        expr: expr,
        rightParenToken: rightParen
      )
    }

    // Gather all the subexpressions.
    var exprs = [BasicExprSyntax]()
    while isStartOfBasicExpr() {
      exprs.append(try parseBasicExpr())
    }

    // If we've not hit the matching closing paren, we must be parsing a typed
    // parameter group
    //
    // (a b c ... : <expr>) {d e f ... : <expr>} ...
    if case .colon = peek() {
      return try self.finishParsingTypedParameterGroupExpr(leftParen, exprs)
    }

    // Else consume the closing paren.
    let rightParen = try consume(.rightParen)

    // If there's only one named expression like '(a)', return it.
    guard exprs.count >= 1 else {
      return ParenthesizedExprSyntax(
        leftParenToken: leftParen,
        expr: exprs[0],
        rightParenToken: rightParen
      )
    }

    // Else form an application expression.
    let app = ApplicationExprSyntax(exprs:
                                    BasicExprListSyntax(elements: exprs))
    return ParenthesizedExprSyntax(
      leftParenToken: leftParen,
      expr: app,
      rightParenToken: rightParen
    )
  }

  func parseExpr() throws -> ExprSyntax {
    switch peek() {
    case .forwardSlash:
      return try self.parseLambdaExpr()
    case .forallSymbol, .forallKeyword:
      return try self.parseQuantifiedExpr()
    case .letKeyword:
      return try self.parseLetExpr()
    default:
      // If we're looking at another basic expr, then we're trying to parse
      // either an application or an -> expression. Either way, parse the
      // remaining list of expressions and construct a BasicExprList with the
      // first expression at the beginning.
      var exprs = [BasicExprSyntax]()
      while isStartOfBasicExpr() || peek() == .arrow {
        // If we see an arrow at the start, then consume it and move on.
        if case .arrow = peek() {
          let arrow = try consume(.arrow)
          let name = QualifiedNameSyntax(elements: [
            QualifiedNamePieceSyntax(name: arrow, trailingPeriod: nil),
          ])
          exprs.append(NamedBasicExprSyntax(name: name))
        } else {
          exprs.append(contentsOf: try parseBasicExprs())
        }
      }

      if exprs.isEmpty {
        throw expected("expression")
      }

      // If there's only one expression in this "application", then just return
      // it without constructing an application.
      guard exprs.count > 1 else {
        return exprs[0]
      }
      return ApplicationExprSyntax(exprs: BasicExprListSyntax(elements: exprs))
    }
  }

  func parseTypedParameterGroupExpr() throws -> TypedParameterGroupExprSyntax {
    let parameters = try parseTypedParameterList()
    guard !parameters.isEmpty else {
      throw expected("type ascription")
    }
    return TypedParameterGroupExprSyntax(
      parameters: parameters
    )
  }

  func finishParsingTypedParameterGroupExpr(
    _ leftParen: TokenSyntax, _ exprs: [ExprSyntax]
  ) throws -> TypedParameterGroupExprSyntax {
    let colonTok = try consume(.colon)

    // Ensure all expressions are simple names
    let names = try exprs.map { expr -> QualifiedNameSyntax in
      guard let namedExpr = expr as? NamedBasicExprSyntax else {
        throw engine.diagnose(.expected("identifier"), node: expr) {
          $0.highlight(expr)
        }
      }
      return namedExpr.name
    }

    let tokens = ensureAllNamesSimple(names)
    let identList = IdentifierListSyntax(elements: tokens)
    let typeExpr = try self.parseExpr()
    let ascription = AscriptionSyntax(boundNames: identList,
                                      colonToken: colonTok,
                                      typeExpr: typeExpr)
    let rightParen = try consume(.rightParen)
    let firstParam = ExplicitTypedParameterSyntax(leftParenToken: leftParen,
                                                  ascription: ascription,
                                                  rightParenToken: rightParen)
    let parameters = try parseTypedParameterList().prepending(firstParam)
    guard !parameters.isEmpty else {
      throw expected("type ascription")
    }
    return TypedParameterGroupExprSyntax(parameters: parameters)
  }

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
    let declList = try parseDeclList()
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
    while isStartOfBasicExpr() {
      pieces.append(try parseBasicExpr())
    }

    guard !pieces.isEmpty else {
      throw expected(diagType)
    }
    return pieces
  }

  func parseBasicExprList() throws -> BasicExprListSyntax {
    return BasicExprListSyntax(elements:
      try parseBasicExprs(diagType: "list of expressions"))
  }

  public func parseBasicExpr() throws -> BasicExprSyntax {
    switch peek() {
    case .underscore:
      return try self.parseUnderscoreExpr()
    case .typeKeyword:
      return try self.parseTypeBasicExpr()
    case .leftParen:
      return try self.parseParenthesizedExpr()
    case .leftBrace:
      return try self.parseTypedParameterGroupExpr()
    case .recordKeyword:
      return try self.parseRecordExpr()
    case .identifier(_):
      return try self.parseNamedBasicExpr()
    default:
      throw expected("expression")
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
    let trailingSemi = try consume(.semicolon)
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

  func parseBindingList() throws -> BindingListSyntax {
    var pieces = [BindingSyntax]()
    while true {
      if isStartOfTypedParameter() {
        pieces.append(try parseTypedBinding())
      } else if case .identifier(_) = peek() {
        pieces.append(try parseNamedBinding())
      } else {
        break
      }
    }

    guard !pieces.isEmpty else {
      throw expected("binding list")
    }

    return BindingListSyntax(elements: pieces)
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
