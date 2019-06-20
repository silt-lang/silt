/// ParseGIR.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Crust
import Seismography
import Moho
import Mantle

public final class GIRParser {
  struct ParserScope {
    let name: String
  }
  let parser: Parser
  var module: GIRModule

  private var _activeScope: ParserScope?
  fileprivate var continuationsByName: [Name: Continuation] = [:]
  fileprivate var undefinedContinuation: [Continuation: TokenSyntax] = [:]
  fileprivate var localValues: [String: Value] = [:]
  fileprivate var forwardRefLocalValues: [String: TokenSyntax] = [:]
  private let tc: TypeChecker<CheckPhaseState>

  var currentScope: ParserScope {
    guard let scope = self._activeScope else {
      fatalError("Attempted to request current scope without pushing a scope.")
    }
    return scope
  }

  public init(_ parser: Parser) {
    self.parser = parser
    self.tc = TypeChecker<CheckPhaseState>(CheckPhaseState(), parser.engine)
    self.module = GIRModule(parent: nil, tc: TypeConverter(self.tc))
  }

  @discardableResult
  func withScope<T>(named name: String,
                    _ actions: () throws -> T) rethrows -> T {
    let prevScope = self._activeScope
    let prevLocals = localValues
    let prevForwardRefLocals = forwardRefLocalValues
    self._activeScope = ParserScope(name: name)

    defer {
      self._activeScope = prevScope
      self.localValues = prevLocals
      self.forwardRefLocalValues = prevForwardRefLocals
    }

    return try actions()
  }

  func namedContinuation(_ B: GIRBuilder, _ name: Name) -> Continuation {
    // If there was no name specified for this block, just create a new one.
    if name.description.isEmpty {
      return B.buildContinuation(name: QualifiedName(name: name))
    }

    // If the block has never been named yet, just create it.
    guard let cont = self.continuationsByName[name] else {
      let cont = B.buildContinuation(name: QualifiedName(name: name))
      self.continuationsByName[name] = cont
      return cont
    }

    if undefinedContinuation.removeValue(forKey: cont) == nil {
      // If we have a redefinition, return a new BB to avoid inserting
      // instructions after the terminator.
      fatalError("Redefinition of Basic Block")
    }

    return cont
  }

  func getReferencedContinuation(
    _ B: GIRBuilder, _ syntax: TokenSyntax) -> Continuation {
    assert(syntax.render.starts(with: "@"))
    let noAtNode = syntax.withKind(
      .identifier(String(syntax.render.dropFirst())))
    let name = Name(name: noAtNode)
    // If the block has already been created, use it.
    guard let cont = self.continuationsByName[name] else {
      // Otherwise, create it and remember that this is a forward reference so
      // that we can diagnose use without definition problems.
      let cont = B.buildContinuation(name: QualifiedName(name: name))
      self.continuationsByName[name] = cont
      self.undefinedContinuation[cont] = syntax
      return cont
    }

    return cont
  }


  func getLocalValue(_ name: TokenSyntax) -> Value {
    // Check to see if this is already defined.
    guard let entry = self.localValues[name.render] else {
      // Otherwise, this is a forward reference.  Create a dummy node to
      // represent it until we see a real definition.
      self.forwardRefLocalValues[name.render] = name
      let entry = NoOp()
      self.localValues[name.render] = entry
      return entry
    }

    return entry
  }

  func setLocalValue(_ value: Value, _ name: String) {
    // If this value was already defined, it is either a redefinition, or a
    // specification for a forward referenced value.
    guard let entry = self.localValues[name] else {
      // Otherwise, just store it in our map.
      self.localValues[name] = value
      return
    }

    guard self.forwardRefLocalValues.removeValue(forKey: name) != nil else {
      fatalError("Redefinition of named value \(name) by \(value)")
    }

    // Forward references only live here if they have a single result.
    entry.replaceAllUsesWith(value)
  }

}

extension GIRParser {
  public func parseTopLevelModule() -> GIRModule {
    do {
      _ = try self.parser.consume(.moduleKeyword)
      let moduleId = try self.parser.parseQualifiedName().render
      _ = try self.parser.consume(.whereKeyword)
      let mod = GIRModule(name: moduleId,
                          parent: nil, tc: TypeConverter(self.tc))
      self.module = mod
      let builder = GIRBuilder(module: mod)
      try self.parseDecls(builder)
      assert(self.parser.currentToken?.tokenKind == .eof)
      return mod
    } catch _ {
      return self.module
    }
  }

  func parseDecls(_ B: GIRBuilder) throws {
    while self.parser.peek() != .rightBrace && self.parser.peek() != .eof {
      _ = try parseDecl(B)
    }
  }

  func parseDecl(_ B: GIRBuilder) throws -> Bool {
    guard
      case let .identifier(identStr) = parser.peek(), identStr.starts(with: "@")
    else {
      throw self.parser.unexpectedToken()
    }
    let ident = try self.parser.parseIdentifierToken()
    _ = try self.parser.consume(.colon)
    _ = try self.parser.parseGIRTypeExpr()
    _ = try self.parser.consume(.leftBrace)
    return try self.withScope(named: ident.render) {
      repeat {
        guard try self.parseGIRBasicBlock(B) else {
          return false
        }
      } while self.parser.peek() != .rightBrace && self.parser.peek() != .eof
      _ = try self.parser.consume(.rightBrace)
      return true
    }
  }

  func parseGIRBasicBlock(_ B: GIRBuilder) throws -> Bool {
    var ident = try self.parser.parseIdentifierToken()
    if ident.render.hasSuffix(":") {
      ident = ident.withKind(.identifier(String(ident.render.dropLast())))
    }
    let cont = self.namedContinuation(B, Name(name: ident))

    // If there is a basic block argument list, process it.
    if try self.parser.consumeIf(.leftParen) != nil {
      repeat {
        let name = try self.parser.parseIdentifierToken().render
        _ = try self.parser.consume(.colon)
        let typeRepr = try self.parser.parseGIRTypeExpr()

        let arg = cont.appendParameter(type: GIRExprType(typeRepr))

        self.setLocalValue(arg, name)
      } while try self.parser.consumeIf(.semicolon) != nil

      _ = try self.parser.consume(.rightParen)
      _ = try self.parser.consume(.colon)
    }

    repeat {
      guard try parseGIRInstruction(B, in: cont) else {
        return true
      }
    } while isStartOfGIRPrimop()
    return true
  }

  func isStartOfGIRPrimop() -> Bool {
    guard case .identifier(_) = self.parser.peek() else {
      return false
    }
    return true
  }

  // swiftlint:disable function_body_length
  func parseGIRInstruction(
    _ B: GIRBuilder, in cont: Continuation) throws -> Bool {
    guard self.parser.peekToken()!.leadingTrivia.containsNewline else {
      fatalError("Instruction must begin on a new line")
    }

    guard case .identifier(_) = self.parser.peek() else {
      return false
    }

    let resultName = tryParseGIRValueName()
    if resultName != nil {
      _ = try self.parser.consume(.equals)
    }

    guard let opcode = parseGIRPrimOpcode() else {
      return false
    }

    var resultValue: Value?
    switch opcode {
    case .dataExtract:
      fatalError("unimplemented")
    case .forceEffects:
      fatalError("unimplemented")
    case .tuple:
      fatalError("unimplemented")
    case .tupleElementAddress:
      fatalError("unimplemented")
    case .thicken:
      fatalError("unimplemented")
    case .noop:
      fatalError("noop cannot be spelled")
    case .alloca:
      let typeRepr = try self.parser.parseGIRTypeExpr()
      let type = GIRExprType(typeRepr)
      resultValue = B.createAlloca(type)
    case .allocBox:
      let typeRepr = try self.parser.parseGIRTypeExpr()
      let type = GIRExprType(typeRepr)
      resultValue = B.createAllocBox(type)
    case .apply:
      guard let fnName = tryParseGIRValueToken() else {
        return false
      }

      let fnVal = self.getLocalValue(fnName)
      _ = try self.parser.consume(.leftParen)

      var argNames = [TokenSyntax]()
      if self.parser.peek() != .rightParen {
        repeat {
          guard let arg = self.tryParseGIRValueToken() else {
            return false
          }
          argNames.append(arg)
        } while try self.parser.consumeIf(.semicolon) != nil
      }
      _ = try self.parser.consume(.rightParen)

      _ = try self.parser.consume(.colon)
      _ = try self.parser.parseGIRTypeExpr()

      var args = [Value]()
      for argName in argNames {
        let argVal = self.getLocalValue(argName)
        args.append(argVal)
      }

      _ = B.createApply(cont, fnVal, args)
    case .copyValue:
      guard let valueName = tryParseGIRValueToken() else {
        return false
      }
      _ = try self.parser.consumeIf(.colon)
      _ = try self.parser.parseGIRTypeExpr()
      resultValue = B.createCopyValue(self.getLocalValue(valueName))
    case .copyAddress:
      guard let valueName = tryParseGIRValueToken() else {
        return false
      }
      _ = try self.parser.consume(.identifier("to"))
      guard let addressName = tryParseGIRValueToken() else {
        return false
      }
      _ = try self.parser.consumeIf(.colon)
      _ = try self.parser.parseGIRTypeExpr()
      resultValue = B.createCopyAddress(self.getLocalValue(valueName),
                                        to: self.getLocalValue(addressName))
    case .dealloca:
      guard let valueName = tryParseGIRValueToken() else {
        return false
      }
      _ = try self.parser.consumeIf(.colon)
      _ = try self.parser.parseGIRTypeExpr()
      cont.appendCleanupOp(B.createDealloca(self.getLocalValue(valueName)))
    case .deallocBox:
      guard let valueName = tryParseGIRValueToken() else {
        return false
      }
      _ = try self.parser.consumeIf(.colon)
      _ = try self.parser.parseGIRTypeExpr()
      cont.appendCleanupOp(B.createDeallocBox(self.getLocalValue(valueName)))
    case .destroyValue:
      guard let valueName = tryParseGIRValueToken() else {
        return false
      }
      _ = try self.parser.consumeIf(.colon)
      _ = try self.parser.parseGIRTypeExpr()
      cont.appendCleanupOp(B.createDestroyValue(self.getLocalValue(valueName)))
    case .destroyAddress:
      guard let valueName = tryParseGIRValueToken() else {
        return false
      }
      _ = try self.parser.consumeIf(.colon)
      _ = try self.parser.parseGIRTypeExpr()
      cont.appendCleanupOp(
        B.createDestroyAddress(self.getLocalValue(valueName)))
    case .switchConstr:
      guard let val = self.tryParseGIRValueToken() else {
        return false
      }
      let srcVal = self.getLocalValue(val)
      _ = try self.parser.consume(.colon)
      _ = try self.parser.parseGIRTypeExpr()

      var caseConts = [(String, FunctionRefOp)]()
      while case .semicolon = self.parser.peek() {
        _ = try self.parser.consume(.semicolon)

        guard
          case let .identifier(ident) = self.parser.peek(), ident == "case"
        else {
          return false
        }
        _ = try self.parser.parseIdentifierToken()

        let caseName = try self.parser.parseQualifiedName()
        _ = try self.parser.consume(.colon)
        guard let arg = self.tryParseGIRValueToken() else {
          return false
        }
        // swiftlint:disable force_cast
        let fnVal = self.getLocalValue(arg) as! FunctionRefOp
        caseConts.append((caseName.render, fnVal))
      }

      _ = B.createSwitchConstr(cont, srcVal, caseConts)
    case .functionRef:
      guard
        case let .identifier(refName) = parser.peek(), refName.starts(with: "@")
      else {
         return false
      }
      let ident = try self.parser.parseIdentifierToken()
      let resultFn = getReferencedContinuation(B, ident)
      resultValue = B.createFunctionRef(resultFn)
    case .dataInit:
      let typeRepr = try self.parser.parseGIRTypeExpr()
      _ = try self.parser.consume(.semicolon)
      let ident = try self.parser.parseQualifiedName()
      let type = GIRExprType(typeRepr)

      var args = [Value]()
      while case .semicolon = self.parser.peek() {
        _ = try self.parser.consume(.semicolon)

        guard let arg = self.tryParseGIRValueToken() else {
          return false
        }
        let argVal = self.getLocalValue(arg)
        _ = try self.parser.consume(.colon)
        _ = try self.parser.parseGIRTypeExpr()
        args.append(argVal)
      }

      resultValue = B.createDataInit(ident.render, type, nil)
    case .projectBox:
      guard let valueName = tryParseGIRValueToken() else {
        return false
      }
      _ = try self.parser.consumeIf(.colon)
      let typeRepr = try self.parser.parseGIRTypeExpr()
      resultValue = B.createProjectBox(self.getLocalValue(valueName),
                                       type: GIRExprType(typeRepr))
    case .load:
      guard let valueName = tryParseGIRValueToken() else {
        return false
      }
      _ = try self.parser.consumeIf(.colon)
      _ = try self.parser.parseGIRTypeExpr()
      resultValue = B.createLoad(self.getLocalValue(valueName), .copy)
    case .store:
      guard let valueName = tryParseGIRValueToken() else {
        return false
      }
      _ = try self.parser.consume(.identifier("to"))
      guard let addressName = tryParseGIRValueToken() else {
        return false
      }
      _ = try self.parser.consumeIf(.colon)
      _ = try self.parser.parseGIRTypeExpr()
      _ = B.createStore(self.getLocalValue(valueName),
                        to: self.getLocalValue(addressName))
    case .unreachable:
      resultValue = B.createUnreachable(cont)
    }

    guard let resName = resultName, let resValue = resultValue else {
      return true
    }
    self.setLocalValue(resValue, resName)
    return true
  }

  func tryParseGIRValueName() -> String? {
    return tryParseGIRValueToken()?.render
  }

  func tryParseGIRValueToken() -> TokenSyntax? {
    guard let result = self.parser.peekToken() else {
      return nil
    }

    guard case let .identifier(ident) = result.tokenKind else {
      return nil
    }

    guard ident.starts(with: "%") else {
      return nil
    }
    self.parser.advance()
    return result
  }

  func parseGIRPrimOpcode() -> PrimOp.Code? {
    guard case let .identifier(ident) = self.parser.peek() else {
      return nil
    }
    guard let opCode = PrimOp.Code(rawValue: ident) else {
      return nil
    }
    _ = self.parser.advance()
    return opCode
  }
}

extension TokenSyntax {
  var render: String {
    return self.triviaFreeSourceText
  }
}

extension QualifiedNameSyntax {
  var render: String {
    var result = ""
    for component in self {
      result += component.triviaFreeSourceText
    }
    return result
  }
}
