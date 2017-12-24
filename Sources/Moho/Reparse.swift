/// Reparse.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere

/// Describes a section of user-defined notation.
///
/// For example, given:
///
/// ```
/// if_then_else_ : ...
/// ```
///
/// We parse this as
/// ```
/// [
///   .identifier("if"),   .wild,
///   .identifier("then"), .wild,
///   .identifier("else"), .wild,
/// ]
/// ```
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

/// Describes the associativity and precedence of a piece of notation.
public struct Fixity {
  let level: PrecedenceLevel
  let assoc: Associativity

  /// Describes the precedence level of a user-defined notation.
  public enum PrecedenceLevel: Comparable, Hashable, CustomStringConvertible {
    /// A special value for the `_->_` declaration.
    case unrelated
    /// The strength this declaration binds at relative to other declarations.
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

  /// Associativity of a user-defined notation
  enum Associativity {
    /// Non-associative
    ///
    /// ```
    /// (x + y + z) => [ERROR]
    /// ```
    case non
    /// Left-associative
    ///
    /// ```
    /// (x + y + z) => ((x + y) + z)
    /// ```
    case left
    /// Right-associative
    ///
    /// ```
    /// (x + y + z) => (x + (y + z))
    /// ```
    case right
  }
}

/// A user-defined notation.
public struct NewNotation: CustomStringConvertible {
  /// The name of the notation.
  let name: Name
  /// The names involved in the body of the notation.
  let names: Set<Name>
  /// The fixity of the notation.
  let fixity: Fixity
  /// An exploded view of the sections of the notation.
  let notation: [NotationSection]

  public var description: String {
    return notation.map({$0.description}).joined()
        + (fixity.assoc == .non ? "": " binds \(fixity.assoc)")
        + " at level \(fixity.level)"
  }
}

extension NameBinding {
  /// Walks the module and registers any encountered user-defined notations in
  /// a scope.
  func walkNotations(
    _ module: ModuleDeclSyntax, _ name: FullyQualifiedName) -> Scope {
    return self.underScope { (scope) -> Scope in
      scope.nameSpace = NameSpace(name)
      for d in module.declList {
        switch d {
        case let node as FunctionDeclSyntax:
          for name in node.ascription.boundNames {
            guard self.lookupLocalName(Name(name: name)) != nil else {
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
        case is NonFixDeclSyntax, is LeftFixDeclSyntax, is RightFixDeclSyntax:
          guard let fd = d as? FixityDeclSyntax else {
            fatalError("Switch case cast bug")
          }
          guard self.bindFixity(fd) else {
            return scope
          }
        default:
          continue
        }
      }
      return scope
    }
  }

  /// Teases apart a name that is known to introduce new notation into the
  /// sections and a set of its name components.
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

  /// Builds a DAG of the notations in a given scope, ordered by precedence.
  func newNotations(
    in scope: Scope,
    filter: NotationFilter = []
  ) -> ([NewNotation], NotationDAG) {
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

        let fixity = fds.fixity
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
}

extension FixityDeclSyntax {
  /// Converts a fixity declaration to an internal fixity.
  var fixity: Fixity {
    let fixity: Fixity
    switch self {
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
      fatalError("Non-exhaustive switch over FixityDecls?")
    }
    return fixity
  }
}

public typealias NotationDAG
  = PrecedenceDAG<Fixity.PrecedenceLevel, NewNotation>

/*
public final class Reparser {
  var opDAG: NotationDAG
}
*/
