/// Reparse.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Crust

/// The `Reparser` is a hand-(un)rolled implementation of
/// Danielsson and Norell's Agda mixfix notation parser (demo'd in the
/// [Parsing Mixfix Operators Paper](http://www.goo.gl/GiqeVX)).
///
/// Given a precedence DAG, ideally with unambiguous terminators (not required),
/// the reparser implicitly generates a grammar and parses it.  For example,
/// given the declarations
///
/// ```
/// infixr 1 _&&_
/// infix 2 _==_
/// infixl 3 _+_, _-_
/// infixl 3 _!
/// infix if_then_else_
/// ```
///
/// The `Reparser` generates the following grammar:
///
/// ```
/// expr   ::= <and> | <eq> | <plus> | <minus> | <bang> | <if> | <closed>
/// and    ::= (<and↑> &&)+ <and↑>
/// and↑   ::= <eq> | <closed>
/// eq     ::= <eq↑> == <eq↑>
/// eq↑    ::= <plus> | <minus> | <bang> | <closed>
/// plus   ::= <closed> (+ <closed>)+
/// minus  ::= <closed> (- <closed>)+
/// bang   ::= <closed> !+
/// if     ::= (if <expr> then <expr> else)+ <closed>
/// closed ::= x | y | z | a | b | c | ... | (<expr>)
/// ```
public final class Reparser {
  enum ParseSide {
    case none
    case lhs
    case rhs
  }
  let engine: DiagnosticEngine
  var index: Int = 0
  var tokens: [TokenSyntax] = []
  var dag: NotationDAG = NotationDAG()
  var closedNames: Set<String> = []
  var originalNode: Syntax?
  var side: ParseSide = .none

  init(engine: DiagnosticEngine) {
    self.engine = engine
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

  var currentToken: TokenSyntax? {
    return index < tokens.count ? tokens[index] : nil
  }

  func consume(_ kinds: TokenKind...) -> TokenSyntax? {
    guard let token = currentToken, kinds.contains(token.tokenKind) else {
      return nil
    }
    advance()
    return token
  }
}

extension Reparser {
  /// Reparses an arbitrary expression appearing on the right-hand side of
  /// either an equal sign or a colon.
  ///
  /// Reparsing may fail and yield a fragment of the total expression so
  /// Scope Check can recover.
  func reparseRHS(
    _ original: Syntax, _ tokens: [TokenSyntax],
    notation dag: NotationDAG, closed: Set<String>
  ) -> ExprSyntax {
    precondition(!dag.isEmpty, "Why are you reparsing with no notation?")

    self.index = 0
    self.originalNode = original
    self.tokens = tokens
    self.dag = dag
    self.closedNames = closed
    self.side = .rhs
    return self.performRHSReparse()
  }

  /// Reparses an arbitrary expression appearing on the left-hand side of
  /// either an equal sign.
  ///
  /// Reparsing may fail and yield a fragment of the total expression so
  /// Scope Check can recover.
  func reparseLHS(
    _ original: Syntax, _ tokens: [TokenSyntax],
    notation dag: NotationDAG, closed: Set<String>
  ) -> (Name, BasicExprListSyntax) {
    precondition(!dag.isEmpty, "Why are you reparsing with no notation?")

    self.index = 0
    self.originalNode = original
    self.tokens = tokens
    self.dag = dag
    self.closedNames = closed
    self.side = .lhs
    return self.performLHSReparse()
  }

  private func performRHSReparse() -> ExprSyntax {
    // Enter the reparser thru the top-level <expr> production.
    let expr = self.parseExpression(at: .unrelated)
    if peek() != .eof {
      self.engine.diagnose(.reparseRHSFailed, node: self.originalNode) {
        guard let original = self.originalNode else {
          return
        }
        $0.highlight(original)

        if let expr = expr {
          $0.note(Diagnostic.Message.reparseAbleToParse(expr), node: original)
        }
        for note in self.dag.tighter(than: .unrelated) {
          $0.note(.reparseUsedNotation(note), node: original)
        }
      }
    }

    if let reparsedApp = expr as? ReparsedApplicationExprSyntax {
      return reparsedApp
    }

    if
      let reparsedParen = expr as? ParenthesizedExprSyntax,
      !reparsedParen.leftParenToken.isPresent,
      !reparsedParen.rightParenToken.isPresent
    {
      return reparsedParen.expr
    }

    return expr!
  }

  private func performLHSReparse() -> (Name, BasicExprListSyntax) {
    // Enter the reparser thru the top-level <expr> production.
    let expr = self.parseExpression(at: .unrelated)
    if peek() != .eof {
      self.engine.diagnose(.reparseLHSFailed, node: self.originalNode) {
        guard let original = self.originalNode else {
          return
        }
        $0.highlight(original)

        if let expr = expr {
          $0.note(Diagnostic.Message.reparseAbleToParse(expr), node: original)
        }
        for note in self.dag.tighter(than: .unrelated) {
          $0.note(.reparseUsedNotation(note), node: original)
        }
      }
    }

    guard let reparsedApp = expr as? ReparsedApplicationExprSyntax else {
      fatalError("\(type(of: expr))")
    }
    let headName = QualifiedName(ast: reparsedApp.head.name).name
    return (headName, reparsedApp.exprs)
  }

  /// Attempts parsing of all operators in the precedence DAG with precedence
  /// greater than or equal to the given level, yielding to the first parser
  /// that is able to accept the token stream as it stands.
  ///
  /// Parsing fails if no user-defined operators or closed names could be
  /// interpreted from the token stream.
  ///
  /// Parsing of conflicting operators of the same precedence may lead to
  /// incomplete consumption of the token buffer.  If not all tokens have been
  /// consumed, the parser was unable to make further forward progress at the
  /// point at which it stopped.
  private func parseExpression(
    at level: Fixity.PrecedenceLevel) -> BasicExprSyntax? {
    guard peek() != .eof else {
      return nil
    }

    for note in self.dag.tighter(than: level) {
      switch note.fixity.assoc {
      case .non:
        guard let expr = self.tryParseNonfix(note) else {
          continue
        }
        return expr
      case .left:
        guard let expr = self.tryParseLeftfix(note) else {
          continue
        }
        return expr
      case .right:
        guard let expr = self.tryParseRightfix(note) else {
          continue
        }
        return expr
      }
    }

    return tryParseClosed()
  }

  // swiftlint:disable large_tuple
  private func sliceNotation(
    _ note: NewNotation) -> (Bool, ArraySlice<NotationSection>, Bool) {
    assert(note.fixity.assoc == .non)
    let wildLeft = note.notation[0].isWild
    let wildRight = note.notation[note.notation.count - 1].isWild
    var seq = ArraySlice(note.notation)
    seq = wildLeft ? seq.dropFirst() : seq
    seq = wildRight ? seq.dropLast() : seq
    return (wildLeft, seq, wildRight)
  }

  /// Attempts to parse a non-associative operator.
  private func tryParseNonfix(_ notation: NewNotation) -> BasicExprSyntax? {
    assert(notation.fixity.assoc == .non)

    let lastPosition = self.index
    var exprs = [BasicExprSyntax]()
    exprs.reserveCapacity(notation.notation.count)

    // First, slice the notation to determine if we have any exterior holes
    // to treat.  These holes must *never* be allowed to recur completely or the
    // parser will eat the stack and crash.
    let (needsLeft, notations, needsRight) = sliceNotation(notation)

    if needsLeft {
      guard let exprL = self.parseExpression(at: notation.fixity.level) else {
        self.index = lastPosition
        return nil
      }
      exprs.append(exprL)
    }

    for sect in notations {
      switch sect {
      case .wild:
        // Internal holes are special: in normal holes you want to parse a
        // terminal so you don't left-recurse to death.  But operators with
        // internal holes act like generalised brackets.  So as long as the
        // precedence DAG has unique name parts we'll always get an unambiguous
        // parse.
        let level = (notation.fixity.level == self.dag.tightest)
                  ? .unrelated
                  : notation.fixity.level
        guard let expr = self.parseExpression(at: level) else {
          return nil
        }
        exprs.append(expr)
      case let .identifier(nm):
        guard case let .identifier(nm2) = peek(), nm.description == nm2 else {
          self.index = lastPosition
          return nil
        }
        advance()
        continue
      }
    }

    if needsRight {
      guard let exprR = self.parseExpression(at: notation.fixity.level) else {
        self.index = lastPosition
        return nil
      }
      exprs.append(exprR)
    }

    let headName = notation.name.syntax.withTrailingTrivia(.spaces(1))
    let headSyntax = SyntaxFactory.makeNamedBasicExpr(name: SyntaxFactory.makeQualifiedNameSyntax([
      SyntaxFactory.makeQualifiedNamePiece(name: headName, trailingPeriod: nil)
    ]))
    let exprList = SyntaxFactory.makeBasicExprListSyntax(exprs)
    return SyntaxFactory.makeReparsedApplicationExpr(head: headSyntax, exprs: exprList)
  }

  /// Attempts to parse a left-associative operator.
  private func tryParseLeftfix(_ notation: NewNotation) -> BasicExprSyntax? {
    assert(notation.fixity.assoc == .left)

    let lastPosition = self.index
    guard let left = self.parseExpression(at: notation.fixity.level) else {
      self.index = lastPosition
      return nil
    }

    return goLeft(notation, left)
  }

  private func goLeft(
    _ notation: NewNotation, _ pre: BasicExprSyntax) -> BasicExprSyntax? {
    let lastPosition = self.index
    var exprs = [BasicExprSyntax]()
    exprs.reserveCapacity(notation.notation.count)
    exprs.append(pre)
    for sect in notation.notation.dropFirst() {
      switch sect {
      case .wild:
        guard let expr = self.parseExpression(at: notation.fixity.level) else {
          self.index = lastPosition
          return nil
        }
        exprs.append(expr)
      case let .identifier(nm):
        if case .arrow = peek(), nm.description == TokenKind.arrow.text {
          advance()
          continue
        }

        guard case let .identifier(nm2) = peek(), nm.description == nm2 else {
          self.index = lastPosition
          return nil
        }
        advance()
        continue
      }
    }

    let headName = notation.name.syntax.withTrailingTrivia(.spaces(1))
    let headSyntax = SyntaxFactory.makeNamedBasicExpr(name: SyntaxFactory.makeQualifiedNameSyntax([
      SyntaxFactory.makeQualifiedNamePiece(name: headName, trailingPeriod: nil)
    ]))

    let exprList = SyntaxFactory.makeBasicExprListSyntax(exprs)
    let left = SyntaxFactory.makeReparsedApplicationExpr(head: headSyntax, exprs: exprList)

    guard let recur = goLeft(notation, left) else {
      let exprList = SyntaxFactory.makeBasicExprListSyntax(exprs)
      return SyntaxFactory.makeReparsedApplicationExpr(head: headSyntax, exprs: exprList)
    }

    return recur
  }

  /// Attempts to parse a right-associative operator.
  private func tryParseRightfix(_ notation: NewNotation) -> BasicExprSyntax? {
    assert(notation.fixity.assoc == .right)

    let lastPosition = self.index
    var exprs = [BasicExprSyntax]()
    exprs.reserveCapacity(notation.notation.count)
    for sect in notation.notation.dropLast() {
      switch sect {
      case .wild:
        guard let expr = self.parseExpression(at: notation.fixity.level) else {
          self.index = lastPosition
          return nil
        }
        exprs.append(expr)
      case let .identifier(nm):
        if case .arrow = peek(), nm.description == TokenKind.arrow.text {
          advance()
          continue
        }

        guard case let .identifier(nm2) = peek(), nm.description == nm2 else {
          self.index = lastPosition
          return nil
        }
        advance()
        continue
      }
    }

    let headName = notation.name.syntax.withTrailingTrivia(.spaces(1))
    let headSyntax = SyntaxFactory.makeNamedBasicExpr(name: SyntaxFactory.makeQualifiedNameSyntax([
      SyntaxFactory.makeQualifiedNamePiece(name: headName, trailingPeriod: nil)
    ]))

    guard let recur = tryParseRightfix(notation) else {
      guard let expr = self.parseExpression(at: notation.fixity.level) else {
        self.index = lastPosition
        return nil
      }
      exprs.append(expr)
      let exprList = SyntaxFactory.makeBasicExprListSyntax(exprs)
      return SyntaxFactory.makeReparsedApplicationExpr(head: headSyntax, exprs: exprList)
    }

    exprs.append(recur)
    let exprList = SyntaxFactory.makeBasicExprListSyntax(exprs)
    return SyntaxFactory.makeReparsedApplicationExpr(head: headSyntax, exprs: exprList)
  }

  /// Closed operators bind strictly tighter than all other user-defined
  /// operators.  Try to consume as many non-operator identifiers as we can.
  private func tryParseClosed() -> BasicExprSyntax? {
    func pumpParse() -> BasicExprSyntax? {
      switch peek() {
      case let .identifier(s) where self.closedNames.contains(s):
        let syntax = consume(peek())!
        return SyntaxFactory.makeNamedBasicExpr(name: SyntaxFactory.makeQualifiedNameSyntax([
          SyntaxFactory.makeQualifiedNamePiece(name: syntax, trailingPeriod: nil)
        ]))
      case .identifier(_):
        return nil
      case .arrow where self.closedNames.contains(TokenKind.arrow.text):
        let syntax = consume(peek())!
        return SyntaxFactory.makeNamedBasicExpr(name: SyntaxFactory.makeQualifiedNameSyntax([
          SyntaxFactory.makeQualifiedNamePiece(name: syntax, trailingPeriod: nil)
        ]))
      case .typeKeyword
        where self.closedNames.contains(TokenKind.typeKeyword.text):
        let syntax = consume(peek())!
        return SyntaxFactory.makeTypeBasicExpr(typeToken: syntax)
      case .rightParen:
        return nil
      case .eof:
        return nil
      default:
        if peek() == .leftParen, let parenExpr = self.parseParenthesized() {
          return parenExpr
        }

        if peek() == .forallKeyword || peek() == .forallSymbol {
          advance()
        }

        return self.engine.transact { () -> (Bool, BasicExprSyntax?) in
          let parse = Parser(diagnosticEngine: self.engine, tokens: self.tokens)
          parse.advance(self.index)

          guard let parsedExpr = try? parse.parseBasicExpr() else {
            return (false, nil)
          }
          self.index = parse.index
          return (false, parsedExpr)
        }
      }
    }
    guard let expr = pumpParse() else {
      return nil
    }

    guard let headExpr = expr as? NamedBasicExprSyntax else {
      return expr
    }

    var exprs = [BasicExprSyntax]()
    while let basicExpr = pumpParse() {
      exprs.append(basicExpr)
    }
    let syntaxList = SyntaxFactory.makeBasicExprListSyntax(exprs)
    return SyntaxFactory.makeReparsedApplicationExpr(head: headExpr,
                                                     exprs: syntaxList)
  }

  /// Parses a parenthesized expression.
  private func parseParenthesized() -> ParenthesizedExprSyntax? {
    let lastIndex = self.index
    guard let leftParen = self.consume(.leftParen) else {
      self.index = lastIndex
      return nil
    }

    guard peek() != .backSlash else {
      self.index = lastIndex
      return nil
    }

    guard let expr = self.parseExpression(at: .unrelated) else {
      self.index = lastIndex
      return nil
    }

    guard let rightParen = self.consume(.rightParen) else {
      self.index = lastIndex
      return nil
    }

    return SyntaxFactory.makeParenthesizedExpr(leftParenToken: leftParen,
                                               expr: expr,
                                               rightParenToken: rightParen)
  }
}

extension NameBinding {
  /// Reparses an arbitrary expression into a head-explicit form that mimics
  /// explicit parentheticals and normal function applications.
  ///
  /// ```
  /// if_then_else_                      if ((b) && (((n) + (n)) == ((n) !)))
  ///   _&&_ b (_==_ (_+_ n n) (_! n))     then (n) else (((((n) + (n)) - (n))))
  ///   (n)                           <=>
  ///   (_-_ (_+_ n n) n)
  /// ```
  func reparseExpr(_ syntax: ExprSyntax) -> ExprSyntax {
    switch syntax {
    case let syntax as LetExprSyntax:
      return syntax.withOutputExpr(self.reparseExpr(syntax.outputExpr))
    default:
      return reparseRHS(syntax)
    }
  }

  func reparseRHS(_ syntax: ExprSyntax) -> ExprSyntax {
    let (toks, activeNotes, closedNames) = retokenize(syntax)
    guard !activeNotes.isEmpty else {
      return syntax
    }

    let dag = NotationDAG()
    for note in activeNotes {
      dag.addVertex(level: note.fixity.level, note)
    }
    return self.reparser.reparseRHS(syntax, toks,
                                    notation: dag, closed: closedNames)
  }

  /// Reparses an expression representing the pattern-binding component of a
  /// function into a head-explicit form that mimics explicit parentheticals
  /// and normal function applications.
  func reparseLHS(
    _ syntax: BasicExprListSyntax) -> (Name, BasicExprListSyntax) {
    let (toks, activeNotes, closedNames) = retokenize(syntax)
    // If the node does not use any notation, we can split it at the function
    // name and return it.
    guard !activeNotes.isEmpty else {
      guard
        let fs = syntax.first,
        let namedSyntax = fs as? NamedBasicExprSyntax
      else {
        fatalError()
      }
      let name = QualifiedName(ast: namedSyntax.name)
      return (name.name, syntax.removingFirst())
    }

    let dag = NotationDAG()
    for note in activeNotes {
      dag.addVertex(level: note.fixity.level, note)
    }
    return self.reparser.reparseLHS(syntax, toks,
                                    notation: dag, closed: closedNames)
  }

  /// Break a syntax node down into a token stream, returning a list of
  /// notations used in the tree and a set of names that act as valid
  /// closed forms in the grammar.
  private func retokenize(
    _ node: Syntax) -> ([TokenSyntax], [NewNotation], Set<String>) {
    var tokens: [TokenSyntax] = []
    var usedNames: Set<String> = []
    retokenizeRec(node, &tokens, &usedNames)
    let notes = self.getNotations(in: self.activeScope)
    let allNoteNames: Set<String> = []
    let closedNames = usedNames.subtracting(notes.reduce(into: allNoteNames, {
      return $0.formUnion($1.names)
    }))
    return (tokens, notes.filter({ note in
      return note.names.isSubset(of: usedNames)
    }), closedNames)
  }

  private func retokenizeRec(
    _ node: Syntax, _ sink: inout [TokenSyntax], _ idents: inout Set<String>) {
    switch node {
    case let node as TokenSyntax:
      if case let .identifier(s) = node.tokenKind {
        idents.insert(s)
      } else if case .arrow = node.tokenKind {
        idents.insert(TokenKind.arrow.text)
      } else if case .typeKeyword = node.tokenKind {
        idents.insert(TokenKind.typeKeyword.text)
      }
      sink.append(node)
    case let node as LambdaExprSyntax:
      sink.append(SyntaxFactory.makeToken(.leftParen, presence: .implicit))
      for child in node.children {
        retokenizeRec(child, &sink, &idents)
      }
      sink.append(SyntaxFactory.makeToken(.rightParen, presence: .implicit))
    default:
      for child in node.children {
        retokenizeRec(child, &sink, &idents)
      }
    }
  }
}
