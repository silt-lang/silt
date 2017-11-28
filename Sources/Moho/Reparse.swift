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
        case _ where d is NonFixDeclSyntax
          || d is LeftFixDeclSyntax
          || d is RightFixDeclSyntax:
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
}

public typealias NotationDAG = DAG<PrecedenceLevel, NewNotation>

/*
public final class Reparser {
  var opDAG: NotationDAG
}
*/
