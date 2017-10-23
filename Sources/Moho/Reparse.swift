//
//  Reparse.swift
//  Moho
//
//  Created by Robert Widmann on 10/28/17.
//
import Lithosphere

public enum NotationSection: CustomStringConvertible {
  case wild
  case identifier(Name)

  public var description: String {
    switch self {
    case .wild: return "_"
    case let .identifier(n): return n.string
    }
  }
}

public enum PrecedenceLevel: Comparable, Hashable, CustomStringConvertible {
  case unrelated
  case related(Int)

  public static func == (lhs: PrecedenceLevel, rhs: PrecedenceLevel) -> Bool {
    switch (lhs, rhs) {
    case (.unrelated, .unrelated): return true
    case let (.related(l), .related(r)): return l == r
    default: return false
    }
  }

  public static func < (lhs: PrecedenceLevel, rhs: PrecedenceLevel) -> Bool {
    switch (lhs, rhs) {
    case (.unrelated, _): return true
    case (_, .unrelated): return false
    case let (.related(l), .related(r)): return l < r
    }
  }

  public var hashValue: Int {
    switch self {
    // FIXME: Hash like an Optional<Int> when Optional<Int> can hash at all
    case .unrelated:
      return Int.max.hashValue
    case let .related(l):
      return l.hashValue
    }
  }

  public static var min: PrecedenceLevel {
    return .related(Int.min)
  }

  public static var max: PrecedenceLevel {
    return .related(Int.max - 1)
  }

  public var description: String {
    switch self {
    case .unrelated: return ""
    case let .related(l): return l.description
    }
  }
}

enum Associativity {
  case non
  case left
  case right
}

struct Fixity {
  let level: PrecedenceLevel
  let assoc: Associativity
}

public struct NewNotation: CustomStringConvertible {
  let name: Name
  let names: Set<Name>
  let fixity: Fixity
  let notation: [NotationSection]

  public var description: String {
    return notation.map({$0.description}).joined()
        + (fixity.assoc == .non ? "": " binds \(fixity.assoc)")
        + " at level \(fixity.level)"
  }
}

extension NameBinding {
  func walkNotations(_ module: ModuleDeclSyntax) -> Scope {
    return self.underScope { (scope) -> Scope in
      for i in 0..<module.declList.count {
        let d = module.declList[i]

        switch d {
        case let node as FunctionDeclSyntax:
          for i in 0..<node.ascription.boundNames.count {
            let name = node.ascription.boundNames[i]
            guard self.bindDefinition(named: Name(name: name), -1) != nil else {
              return scope
            }
            guard name.sourceText.contains("_" as Character) else {
              continue
            }

            let defaultFix = NonFixDeclSyntax(
              infixToken: TokenSyntax(.infixKeyword),
              precedence: TokenSyntax(.identifier("20")),
              names: IdentifierListSyntax(elements: [ name ]),
              trailingSemicolon: TokenSyntax(.semicolon)
            )
            guard self.bindFixity(defaultFix) else {
              return scope
            }
          }
        case _ where d is NonFixDeclSyntax
          || d is LeftFixDeclSyntax
          || d is RightFixDeclSyntax:
          guard self.bindFixity(d as! FixityDeclSyntax) else {
            return scope
          }
        default:
          continue
        }
      }
      return scope
    }
  }

  private func teaseNotation(_ not: Name) -> ([NotationSection], Set<Name>) {
    var secs = [NotationSection]()
    var names = Set<Name>()
    var startIdx: String.Index? = nil
    var endIdx: String.Index? = nil
    for i in not.string.indices {
      guard not.string[i] != "_" else {
        if let start = startIdx, let end = endIdx {
          let section = String(not.string[start...end])
          let partTok = TokenSyntax(.identifier(section))
          let partName = Name(name: partTok)
          secs.append(.identifier(partName))
          names.insert(partName)
        }

        secs.append(.wild)
        startIdx = nil
        endIdx = nil
        continue
      }

      guard startIdx != nil, let end = endIdx else {
        startIdx = i
        endIdx = i
        continue
      }
      endIdx = not.string.index(after: end)
    }

    if let end = endIdx, let start = startIdx, end != not.string.endIndex {
      let section = String(not.string[start..<not.string.endIndex])
      let partTok = TokenSyntax(.identifier(section))
      let partName = Name(name: partTok)
      secs.append(.identifier(partName))
      names.insert(partName)
    }

    return (secs, names)
  }

  struct NotationFilter: OptionSet {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
      self.rawValue = rawValue
    }

    public static let constructors = NotationFilter(rawValue: 1 << 0)
  }

  func newNotations(in scope: Scope, filter: NotationFilter = []) -> ([NewNotation], NotationDAG) {
    return self.withScope(scope) { scope in
      var notes = [NewNotation]()
      notes.reserveCapacity(scope.fixities.count)
      let dag = NotationDAG()
      for (name, fds) in scope.fixities {
        guard let (_, info) = self.lookupLocalName(name) else {
          fatalError("Bound non-local identifier name?")
        }

        if filter.contains(.constructors) && !info.isConstructor {
          continue
        }

        let fixity: Fixity
        switch fds {
        case let fds as NonFixDeclSyntax:
          guard
            case let .identifier(num) = fds.precedence.tokenKind,
            let prec = Int(num, radix: 10)
            else {
              fatalError()
          }
          fixity = Fixity(level: .related(prec), assoc: .non)
        case let fds as RightFixDeclSyntax:
          guard
            case let .identifier(num) = fds.precedence.tokenKind,
            let prec = Int(num, radix: 10)
            else {
              fatalError()
          }
          fixity = Fixity(level: .related(prec), assoc: .right)
        case let fds as LeftFixDeclSyntax:
          guard
            case let .identifier(num) = fds.precedence.tokenKind,
            let prec = Int(num, radix: 10)
            else {
              fatalError()
          }
          fixity = Fixity(level: .related(prec), assoc: .left)
        default:
          fatalError()
        }
        let (secs, names) = teaseNotation(name)
        let notation = NewNotation(name: name, names: names, fixity: fixity,
                                   notation: secs)
        notes.append(notation)
        dag.addVertex(level: fixity.level, notation)
      }

      // FIXME: Need to internally define arrows
      let arrowNoteName = Name(name: TokenSyntax(.identifier("_->_")))
      let arrowName = Name(name: TokenSyntax(.arrow))
      let arrowNotation = NewNotation(
        name: arrowNoteName,
        names: [arrowName],
        fixity: Fixity(level: .min, assoc: .right),
        notation: [.wild, .identifier(arrowName), .wild])
      dag.addVertex(level: .min, arrowNotation)

      return (notes, dag)
    }
  }

  func reparseDecls(_ ds: DeclListSyntax) -> DeclListSyntax {
    var decls = [DeclSyntax]()
    let notes = self.newNotations(in: self.activeScope)
    let reparser = Reparser(notes.1)
    var funcMap = [Name: FunctionDeclSyntax]()
    var clauseMap = [Name: [FunctionClauseDeclSyntax]]()
    for i in 0..<ds.count {
      let decl = ds[i]
      switch decl {
      case let decl as FunctionDeclSyntax:
        let reparsed = self.reparseExpr(decl.ascription.typeExpr, with: reparser)
        let funcDecl = decl.withAscription(decl.ascription.withTypeExpr(reparsed))
        for i in 0..<funcDecl.ascription.boundNames.count {
          let name = Name(name: funcDecl.ascription.boundNames[i])
          guard clauseMap[name] == nil else {
            self.engine.diagnose(.nameShadows(name))
            fatalError()
          }
          funcMap[name] = funcDecl
          clauseMap[name] = []
        }
      case let decl as NormalFunctionClauseDeclSyntax:
        let pat = lookThroughParens(self.reparseExpr(ApplicationExprSyntax(exprs: decl.basicExprList), with: reparser)) as! ReparsedApplicationExprSyntax
        let funcDecl = decl.withBasicExprList(pat.exprs)

        guard let namedExpr = pat.exprs[0] as? NamedBasicExprSyntax else {
          fatalError()
        }
        let name = QualifiedName(ast: namedExpr.name).name
        guard clauseMap[name] != nil else {
          self.engine.diagnose(.bodyBeforeSignature(name))
          fatalError()
        }
        clauseMap[name]!.append(funcDecl)
      default:
        fatalError()
      }
    }

    for k in funcMap.keys {
      let function = funcMap[k]!
      let clauses = clauseMap[k]!
      let singleton = IdentifierListSyntax(elements: [ k.syntax ])
      decls.append(ReparsedFunctionDeclSyntax(
        ascription: function.ascription.withBoundNames(singleton),
        trailingSemicolon: function.trailingSemicolon,
        clauseList: FunctionClauseListSyntax(elements: clauses)))
    }

    return DeclListSyntax(elements: decls)
  }

  private func reparseExpr(_ e: ExprSyntax, with reparser: Reparser) -> ExprSyntax {
    switch e {
    case let e as NamedBasicExprSyntax:
      return e
    case let e as TypedParameterArrowExprSyntax:
      return e.withOutputExpr(reparseExpr(e.outputExpr, with: reparser))
    case let e as ApplicationExprSyntax:
      guard let synt = reparser.parse(e) else {
        fatalError()
      }
      print(e.sourceText, " <=> ", synt.sourceText)
      return synt
    case let e as QuantifiedExprSyntax:
      return e.withOutputExpr(reparseExpr(e.outputExpr, with: reparser))
    default:
      print(type(of: e))
      fatalError()
    }
  }
}

public typealias NotationDAG = DAG<PrecedenceLevel, NewNotation>

public final class Reparser {
  var opDAG: NotationDAG
  var tokens = BasicExprListSyntax(elements: [])
  var index = 0
  let sharedClosedDriver = ClosedExprDriver()
  var topLevelDriver: TopLevelDisjunctDriver! = nil

  init(_ dag: NotationDAG) {
    self.opDAG = dag
    self.topLevelDriver = self.buildDriver()

    self.topLevelDriver.closed = self.sharedClosedDriver
    self.sharedClosedDriver.topLevel = self.topLevelDriver
  }

  deinit {
    self.sharedClosedDriver.topLevel = nil
    self.topLevelDriver.closed = nil
  }

  func parse(_ app: ApplicationExprSyntax) -> BasicExprSyntax? {
    self.index = 0
    self.tokens = app.exprs

    var closedDrivers = [Driver]()
    for i in 0..<app.exprs.count {
      let be = app.exprs[i]
      if let nbe = be as? NamedBasicExprSyntax, !nbe.sourceText.hasPrefix("->") {
        let name = QualifiedName(ast: nbe.name).name
        closedDrivers.append(ClosedNameDriver(name))
      }
    }
    closedDrivers.append(AnyUnnamedExprDriver())
    self.sharedClosedDriver.expr = DisjunctDriver(closedDrivers)

    guard let e = self.topLevelDriver.recognize(self), self.currentToken == nil else {
      return ReparsedApplicationExprSyntax(exprs: app.exprs)
    }
    return e
  }

  public func dump(_ node: Syntax, _ toks: inout [TokenSyntax]) {
    switch node {
    case let node as TokenSyntax:
      toks.append(node)
    default:
      for child in node.children {
        dump(child, &toks)
      }
    }
  }

  func buildDriver() -> TopLevelDisjunctDriver {
    let tighter = self.opDAG.tighter(than: .unrelated)
    var allDrivers = [Driver]()
    for t in tighter {
      allDrivers.append(self.buildDriverImpl(t))
    }
    return TopLevelDisjunctDriver(allDrivers)
  }

  private func buildDriverImpl(_ root: NewNotation) -> Driver {
    let tighter = self.opDAG.tighter(than: root.fixity.level)

    let subP: Driver
    if tighter.isEmpty {
      subP = self.sharedClosedDriver
    } else {
      subP = DisjunctDriver(tighter.map(self.buildDriverImpl))
    }

    var drivers = [Driver]()
    for sect in root.notation {
      switch sect {
      case .wild:
        drivers.append(subP)
      case let .identifier(n):
        drivers.append(OpPieceDriver(n))
      }
    }
    return NonAssocDriver(root, drivers)

//    var drivers = [Driver]()
//    switch root.fixity.assoc {
//    case .non:
//      for sect in root.notation {
//        switch sect {
//        case .wild:
//          drivers.append(subP)
//        case let .identifier(n):
//          drivers.append(NamedDriver(n))
//        }
//      }
//      return NonAssocDriver(root, drivers)
//    case .right:
//      switch root.notation.first! {
//      case .wild:
//        drivers.append(subP)
//      case let .identifier(n):
//        drivers.append(NamedDriver(n))
//      }
//
//      var subDrivers = [Driver]()
//      for sect in root.notation.dropFirst() {
//        switch sect {
//        case .wild:
//          subDrivers.append(subP)
//        case let .identifier(n):
//          subDrivers.append(NamedDriver(n))
//        }
//      }
//      drivers.append(Many1Driver(SequencedDriver(subDrivers)))
//      return RightAssocDriver(root, drivers)
//    case .left:
//      var subDrivers = [Driver]()
//      for sect in root.notation.dropLast() {
//        switch sect {
//        case .wild:
//          subDrivers.append(subP)
//        case let .identifier(n):
//          subDrivers.append(NamedDriver(n))
//        }
//      }
//
//      drivers.append(Many1Driver(SequencedDriver(subDrivers)))
//
//      switch root.notation.last! {
//      case .wild:
//        drivers.append(subP)
//      case let .identifier(n):
//        drivers.append(NamedDriver(n))
//      }
//      return LeftAssocDriver(root, drivers)
//    }
  }

  var currentToken: BasicExprSyntax? {
    return index < tokens.count ? tokens[index]: nil
  }

  func consume(_ kinds: BasicExprSyntax.Type...) -> BasicExprSyntax? {
    guard let token = currentToken else {
      return nil
    }
    guard kinds.first(where: { $0 === type(of: token) }) != nil else {
      return nil
    }
    advance()
    return token
  }

  private func advance(_ n: Int = 1) {
    self.index += n
  }

  class Driver: CustomStringConvertible {
    func recognize(_ x: Reparser) -> BasicExprSyntax? {
      fatalError("Grammar schemata must override recognizer!")
    }

    var description: String {
      fatalError("Grammar schemata must override description!")
    }
  }
  class EmptyDriver: Driver {
    override func recognize(_ x: Reparser) -> BasicExprSyntax? { return nil }

    override var description: String { return "⊥" }
  }
  class AnyUnnamedExprDriver: Driver {
    override func recognize(_ x: Reparser) -> BasicExprSyntax? {
      guard let t = x.currentToken else {
        return nil
      }

      guard !(t is NamedBasicExprSyntax || t is ParenthesizedExprSyntax) else {
        return nil
      }

      x.advance()
      return t
    }

    override var description: String { return "" }
  }
  class ClosedNameDriver: Driver {
    let name: Name
    init(_ t: Name) { self.name = t }

    override var description: String { return self.name.string }

    override func recognize(_ x: Reparser) -> BasicExprSyntax? {
      guard let t = x.currentToken else {
        return nil
      }

      guard let tok = t as? NamedBasicExprSyntax else {
        return nil
      }

      guard QualifiedName(ast: tok.name).name == self.name else {
        return nil
      }
      x.advance()
      return tok
    }
  }
  class OpPieceDriver: ClosedNameDriver {}
  class SequencedDriver: Driver {
    let ds: [Driver]
    init(_ ds: [Driver]) {
      precondition(!ds.isEmpty)
      self.ds = ds
    }

    override func recognize(_ x: Reparser) -> BasicExprSyntax? {
//      let previousPosition = x.index
//      for d in ds {
//        guard d.recognize(x) else {
//          x.index = previousPosition
//          return nil
//        }
//      }
//      return true
      return nil
    }

    var label: String {
      for d in ds {
        if let named = d as? ClosedNameDriver {
          return "Class_" + named.name.string
        }

//        if let many1 = d as? Many1Driver {
//          if let nestedSub = many1.d as? SequencedDriver {
//            for sub in nestedSub.ds {
//              if let named = sub as? NamedDriver {
//                return "Class_" + named.name.string
//              }
//            }
//          }
//        }
      }
      return ""
    }

    override var description: String {
      return self.ds.map({ d in
        if let disD = d as? DisjunctDriver, !disD.ds.isEmpty {
          var disd = [String]()
          for disjunct in disD.ds {
            if let nestSeq = disjunct as? SequencedDriver {
              disd.append(nestSeq.label)
            } else if !(disjunct is DisjunctDriver) {
              disd.append(d.description)
            }
          }
          return self.label + "↑"
        }
        return d.description
      }).joined(separator: " ")
    }
  }

  class NonAssocDriver: SequencedDriver {
    let note: NewNotation
    init(_ note: NewNotation, _ ds: [Driver]) {
      self.note = note
      super.init(ds)
    }
    override func recognize(_ x: Reparser) -> BasicExprSyntax? {
      let previousPosition = x.index
      var exprs = [BasicExprSyntax]()
      let name = QualifiedNameSyntax(elements: [
        QualifiedNamePieceSyntax(name: self.note.name.syntax, trailingPeriod: nil),
      ])
      exprs.append(NamedBasicExprSyntax(name: name))
      for d in ds {
        guard let val = d.recognize(x) else {
          x.index = previousPosition
          return nil
        }
        guard !(d is OpPieceDriver) else {
          continue
        }
        exprs.append(val)
      }
      return parens(ReparsedApplicationExprSyntax(exprs: BasicExprListSyntax(elements: exprs)))
    }
  }

  class DisjunctDriver: Driver {
    let ds: [Driver]

    init(_ ds: [Driver]) { self.ds = ds }

    override func recognize(_ x: Reparser) -> BasicExprSyntax? {
      for d in ds {
        let previousPosition = x.index
        guard let val = d.recognize(x) else {
          x.index = previousPosition
          continue
        }
        return val
      }
      return nil
    }

    override var description: String {
      return self.ds.map({ $0.description }).joined(separator: " | ")
    }
  }
  class TopLevelDisjunctDriver: DisjunctDriver {
    var closed: ClosedExprDriver?

    override init(_ ds: [Driver]) {
      super.init(ds)
    }

    override func recognize(_ x: Reparser) -> BasicExprSyntax? {
      guard let closedDriver = closed else {
        fatalError("Should have tied the knot by now")
      }
      return super.recognize(x) ?? closedDriver.recognize(x)
    }

    override var description: String {
      let allSchemes = "| Exprs: " + self.ds.map({ d in
        if let nestedSeq = d as? SequencedDriver {
          return nestedSeq.label
        }
        return d.description
      }).joined(separator: " | ")
      return allSchemes + "\n| " + self.ds.map({ d in
        if let nestedSeq = d as? SequencedDriver {
          return nestedSeq.label + ": " + d.description
        }
        return d.description
      }).joined(separator: "\n| ")
    }
  }

//  class Many1Driver: Driver {
//    let d: Driver
//    init(_ d: Driver) { self.d = d }
//
//    override func recognize(_ x: Reparser) -> BasicExprSyntax? {
//      guard d.recognize(x) else {
//        return nil
//      }
//      while d.recognize(x) {}
//      return true
//    }
//
//    override var description: String {
//      return "(" + self.d.description + ")+"
//    }
//  }
  class ClosedExprDriver: Driver {
    var expr: DisjunctDriver?
    var topLevel: TopLevelDisjunctDriver?

    override func recognize(_ x: Reparser) -> BasicExprSyntax? {
      guard let exprDriver = expr, let topLevelDriver = topLevel else {
        fatalError("Should have tied the knot by now")
      }
      if let val = exprDriver.recognize(x) {
        return val
      }

      guard
        let tok = x.currentToken,
        let parenth = tok as? ParenthesizedExprSyntax
      else {
        return nil
      }
      guard let app = parenth.expr as? ApplicationExprSyntax else {
        x.advance()
        return parenth
      }

      return Reparser(x.opDAG).parse(app).map(parens)
    }

    override var description: String {
      return "Closed"
    }
  }
}

private func parens(_ be: BasicExprSyntax) -> ParenthesizedExprSyntax {
  return ParenthesizedExprSyntax(
          leftParenToken: TokenSyntax(.leftParen),
          expr: be,
          rightParenToken: TokenSyntax(.rightParen))
}

private func lookThroughParens(_ e: ExprSyntax) -> ExprSyntax {
  var expr = e
  while let paren = expr as? ParenthesizedExprSyntax {
    expr = paren.expr
  }
  return expr
}
