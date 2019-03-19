/// Demangler.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

private let MAXIMUM_SUBST_REPEAT_COUNT = 2048

public final class Demangler {
  public final class Node {
    public enum Kind: Hashable {
      case global
      case identifier(String)

      case module(String)
      case data
      case function

      case tuple
      case emptyTuple
      case firstElementMarker
      case tupleElement
      case type
      case bottomType
      case typeType
      case functionType
      case argumentTuple
      case substitutedType
    }

    let kind: Kind
    var children: [Node] = []

    public init(_ kind: Kind) {
      self.kind = kind
    }

    func addChild(_ node: Node) {
      self.children.append(node)
    }

    func reverseChildren() {
      self.children.reverse()
    }

    fileprivate func contains(_ kind: Kind) -> Bool {
      guard self.kind != kind else {
        return true
      }

      return self.children.contains { $0.contains(kind) }
    }

    public func print(to stream: TextOutputStream) {
      return Printer(root: self, stream: stream).printRoot()
    }

    final class Printer {
      let root: Node
      var stream: TextOutputStream

      init(root: Node, stream: TextOutputStream) {
        self.root = root
        self.stream = stream
      }
    }
  }

  private let buffer: Data
  private var position = 0

  private var nodeStack = [Node]()
  private var substitutions = [Node]()

  private var substitutionBuffer = [String]()
  private var nextWordIdx = 0

  public init(_ text: Data) {
    self.substitutionBuffer = [String](repeating: "",
                                       count: MAXIMUM_WORDS_CAPACITY)
    self.nodeStack.reserveCapacity(16)
    self.substitutions.reserveCapacity(16)
    self.buffer = text
  }

  public static func demangleSymbol(_ mangledName: String) -> Node? {
    let dem = Demangler(mangledName.data(using: .utf8)!)

    let prefixLength = dem.getManglingPrefixLength(mangledName)
    guard prefixLength > 0 else {
      return nil
    }
    dem.position += prefixLength

    if !dem.demangleTopLevel() {
      return nil
    }

    let topLevel = dem.createNode(.global)
    for nd in dem.nodeStack {
      switch nd.kind {
      case .type:
        topLevel.addChild(nd.children.first!)
      default:
        topLevel.addChild(nd)
      }
    }

    guard !topLevel.children.isEmpty else {
      return nil
    }

    return topLevel
  }
}

// MARK: Core Demangling Routines

fileprivate extension Demangler {
  func demangleTopLevel() -> Bool {
    while self.position < self.buffer.count {
      guard let node = self.demangleEntity() else {
        return false
      }
      pushNode(node)
    }
    return true
  }

  func demangleEntity() -> Node? {
    switch nextChar() {
    case ManglingScalars.UPPERCASE_A:
      return self.demangleSubstitutions()
    case ManglingScalars.UPPERCASE_B:
      return createNode(.type, [createNode(.bottomType)])
    case ManglingScalars.UPPERCASE_D:
      return self.demangleDataType()
    case ManglingScalars.UPPERCASE_F:
      return self.demangleFunction()
    case ManglingScalars.LOWERCASE_F:
      return self.demangleFunctionType()
    case ManglingScalars.UPPERCASE_G:
      return self.demangleBoundGenericType()
    case ManglingScalars.UPPERCASE_T:
      return self.createNode(.type, [createNode(.typeType)])
    case ManglingScalars.LOWERCASE_T:
      return self.popTuple()
    case ManglingScalars.LOWERCASE_Y:
      return self.createNode(.emptyTuple)
    case ManglingScalars.UNDERSCORE:
      return self.createNode(.firstElementMarker)
    default:
      pushBack()
      return demangleIdentifier()
    }
  }

  func demangleNumber() -> Int? {
    guard peekChar().isDigit else {
      return nil
    }
    var number = 0
    while true {
      let c = peekChar()
      guard c.isDigit else {
        return number
      }
      let newNum = (10 * number) + Int(c - ManglingScalars.ZERO)
      if newNum < number {
        return nil
      }
      number = newNum
      nextChar()
    }
  }

  func demangleIdentifier() -> Node? {
    var hasWordSubsts = false
    var isPunycoded = false
    let c = peekChar()
    guard c.isDigit else {
      return nil
    }

    if c == ManglingScalars.ZERO {
      nextChar()
      if peekChar() == ManglingScalars.ZERO {
        nextChar()
        isPunycoded = true
      } else {
        hasWordSubsts = true
      }
    }
    var result = ""
    repeat {
      while hasWordSubsts && peekChar().isLetter {
        let c = nextChar()
        let proposedIdx: Int
        if c.isLowerLetter {
          proposedIdx = Int(c - ManglingScalars.LOWERCASE_A)
        } else {
          assert(c.isUpperLetter)
          proposedIdx = Int(c - ManglingScalars.UPPERCASE_A)
          hasWordSubsts = false
        }
        guard proposedIdx < self.nextWordIdx else {
          return nil
        }
        assert(proposedIdx < MAXIMUM_WORDS_CAPACITY)
        let cachedWord = self.substitutionBuffer[Int(proposedIdx)]
        result.append(cachedWord)
      }

      if nextIf(ManglingScalars.ZERO) {
        break
      }
      guard let numChars = demangleNumber() else {
        return nil
      }
      if isPunycoded {
        nextIf(ManglingScalars.DOLLARSIGN)
      }
      guard self.position + numChars <= buffer.count else {
        return nil
      }
      let sliceData = buffer.subdata(in: position..<position + numChars)
      let slice = String(data: sliceData, encoding: .utf8)!
      guard !isPunycoded else {
        let punycoder = Punycode()
        guard let punyString = punycoder.decode(utf8String: slice.utf8) else {
          return nil
        }

        result.append(punyString)
        self.position += numChars
        continue
      }

      result.append(slice)
      var wordStartPos: Int?
      for idx in 0...sliceData.count {
        let c = idx < sliceData.count ? sliceData[idx] : 0
        guard let startPos = wordStartPos else {
          if c.isStartOfWord {
            wordStartPos = idx
          }
          continue
        }

        if ManglingScalars.isEndOfWord(c, sliceData[idx - 1]) {
          if idx - startPos >= 2 && self.nextWordIdx < MAXIMUM_WORDS_CAPACITY {
            let wordData = sliceData.subdata(in: startPos..<idx)
            let wordString = String(data: wordData, encoding: .utf8)!
            self.substitutionBuffer[self.nextWordIdx] = wordString
            self.nextWordIdx += 1
          }
          wordStartPos = nil
        }
      }
      self.position += numChars
    } while hasWordSubsts

    guard !result.isEmpty else {
      return nil
    }

    let identNode = createNode(.identifier(result))
    addSubstitution(identNode)
    return identNode
  }
}

// MARK: Demangling Substitutions

fileprivate extension Demangler {
  func demangleSubstitutions() -> Node? {
    var repeatCount = -1
    while true {
      switch nextChar() {
      case 0:
        // End of text.
        return nil
      case let c where c.isLowerLetter:
        let lowerLetter = Int(c - ManglingScalars.LOWERCASE_A)
        guard let subst = pushSubstitutions(repeatCount, lowerLetter) else {
          return nil
        }
        pushNode(subst)
        repeatCount = -1
        // Additional substitutions follow.
        continue
      case let c  where c.isUpperLetter:
        let upperLetter = Int(c - ManglingScalars.UPPERCASE_A)
        // No more additional substitutions.
        return pushSubstitutions(repeatCount, upperLetter)
      case let c where c == ManglingScalars.DOLLARSIGN:
        // The previously demangled number is the large (> 26) index of a
        // substitution.
        let idx = repeatCount + 26 + 1
        guard idx < self.substitutions.count else {
          return nil
        }
        return self.substitutions[idx]
      default:
        pushBack()
        // Not a letter? Then it's the repeat count (no underscore)
        // or a large substitution index (underscore).
        guard let nextRepeatCount = demangleNumber() else {
          return nil
        }
        repeatCount = nextRepeatCount
      }
    }
  }

  func pushSubstitutions(_ repeatCount: Int, _ idx: Int) -> Node? {
    guard idx < self.substitutions.count else {
      return nil
    }
    guard repeatCount <= MAXIMUM_SUBST_REPEAT_COUNT else {
      return nil
    }

    let substitutedNode = self.substitutions[idx]
    guard 0 < repeatCount else {
      return substitutedNode
    }

    for _ in 0..<repeatCount {
      pushNode(substitutedNode)
    }
    return substitutedNode
  }
}

// MARK: Demangling Declarations

fileprivate extension Demangler {
  func popTuple() -> Node? {
    let root = createNode(.tuple)

    var firstElem = false
    repeat {
      firstElem = popNode(.firstElementMarker) != nil
      let tupleElmt = createNode(.tupleElement)
      guard let type = popNode(.type) else {
        return nil
      }

      tupleElmt.addChild(type)
      root.addChild(tupleElmt)
    } while (!firstElem)

    root.reverseChildren()

    return createNode(.type, [root])
  }

  func popModule() -> Node? {
    if let ident = popNode(), case let .identifier(text) = ident.kind {
      return createNode(.module(text))
    }
    return popNode({ $0.kind.isModule })
  }

  func popContext() -> Node? {
    if let module = popModule() {
      return module
    }

    guard let type = popNode(.type) else {
      return popNode({ $0.kind.isContext })
    }
    guard type.children.count == 1 else {
      return nil
    }
    guard let child = type.children.first else {
      return nil
    }
    guard child.kind.isContext else {
      return nil
    }
    return child
  }

  func demangleDataType() -> Node? {
    guard let name = popNode({ $0.kind.isIdentifier }) else {
      return nil
    }
    guard let context = popContext() else {
      return nil
    }
    let type = createNode(.type, [createNode(.data, [context, name])])
    addSubstitution(type)
    return type
  }

  func demangleFunction() -> Node? {
    guard let type = popNode(.type) else {
      return nil
    }

    guard let fnType = type.children.first, fnType.kind == .functionType else {
      return nil
    }

    guard let name = popNode({ $0.kind.isIdentifier }) else {
      return nil
    }

    guard let context = popContext() else {
      return nil
    }

    return createNode(.function, [context, name, type])
  }

  func demangleFunctionType() -> Node? {
    let funcType = createNode(.functionType)
    if let params = demangleFunctionPart(.argumentTuple) {
      funcType.addChild(params)
    }
    guard let returnType = popNode(.type) else {
      return nil
    }
    funcType.addChild(returnType)
    return createNode(.type, [funcType])
  }

  func demangleFunctionPart(_ kind: Node.Kind) -> Node? {
    let type: Node
    if popNode(.emptyTuple) != nil {
      type = createNode(.type, [createNode(.tuple)])
    } else {
      type = popNode(.type)!
    }

    return createNode(kind, [type])
  }

  func demangleBoundGenericType() -> Node? {
    guard let nominal = popNode(.type)?.children[0] else {
      return nil
    }
    var typeList = [Node]()
    if popNode(.emptyTuple) == nil {
      let type = popNode(.type)!
      if type.children[0].kind == .tuple {
        typeList.append(contentsOf: type.children[0].children)
      } else {
        typeList.append(type.children[0])
      }
    }
    let args = createNode(.argumentTuple, typeList)
    switch nominal.kind {
    case .data:
      let boundNode = createNode(.substitutedType, [nominal, args])
      let nty = createNode(.type, [boundNode])
      self.addSubstitution(nty)
      return nty
    default:
      fatalError()
    }
  }

}

// MARK: Parsing

fileprivate extension Demangler {
  func peekChar() -> UInt8 {
    guard self.position < self.buffer.count else {
      return 0
    }
    return self.buffer[position]
  }

  @discardableResult
  func nextChar() -> UInt8 {
    guard self.position < self.buffer.count else {
      return 0
    }
    defer { self.position += 1 }
    return buffer[position]
  }

  @discardableResult
  func nextIf(_ c: UInt8) -> Bool {
    guard peekChar() == c else {
      return false
    }
    self.position += 1
    return true
  }

  func pushBack() {
    assert(position > 0)
    position -= 1
  }

  func consumeAll() -> String {
    let str = buffer.dropFirst(position)
    self.position = buffer.count
    return String(bytes: str, encoding: .utf8)!
  }
}

// MARK: Manipulating The Node Stack

fileprivate extension Demangler {
  func createNode(_ k: Node.Kind, _ children: [Node] = []) -> Node {
    let node = Node(k)
    for child in children {
      node.addChild(child)
    }
    return node
  }

  func pushNode(_ Nd: Node) {
    nodeStack.append(Nd)
  }

  func popNode() -> Node? {
    return self.nodeStack.popLast()
  }

  func popNode(_ kind: Node.Kind) -> Node? {
    guard let lastNode = nodeStack.last else {
      return nil
    }

    guard lastNode.kind == kind else {
      return nil
    }

    return popNode()
  }

  func popNode(_ pred: (Node) -> Bool) -> Node? {
    guard let lastNode = nodeStack.last else {
      return nil
    }

    guard pred(lastNode) else {
      return nil
    }

    return popNode()
  }

  private func addSubstitution(_ Nd: Node) {
    self.substitutions.append(Nd)
  }


  private func getManglingPrefixLength(_ mangledName: String) -> Int {
    guard !mangledName.isEmpty else {
      return 0
    }

    guard mangledName.starts(with: MANGLING_PREFIX) else {
      return 0
    }

    return MANGLING_PREFIX.count
  }
}

// MARK: Demangler Node Attributes

fileprivate extension Demangler.Node.Kind {
  var isContext: Bool {
    switch self {
    case .data:
      return true
    case .function:
      return true
    case .module(_):
      return true
    case .substitutedType:
      return true

    case .global:
      return false
    case .identifier(_):
      return false
    case .tuple:
      return false
    case .emptyTuple:
      return false
    case .firstElementMarker:
      return false
    case .tupleElement:
      return false
    case .type:
      return false
    case .bottomType:
      return false
    case .typeType:
      return false
    case .functionType:
      return false
    case .argumentTuple:
      return false
    }
  }

  var isModule: Bool {
    switch self {
    case .module(_):
      return true
    default:
      return false
    }
  }

  var isIdentifier: Bool {
    switch self {
    case .identifier(_):
      return true
    default:
      return false
    }
  }
}

// MARK: Printing

extension Demangler.Node.Printer {
  func printRoot() {
    print(self.root)
  }

  func print(_ node: Demangler.Node) {
    switch node.kind {
    case .global:
      printChildren(node.children)

    case let .identifier(str):
      self.stream.write(str)
    case let .module(str):
      self.stream.write(str)

    case .data:
      let ctx = node.children[0]
      let name = node.children[1]
      print(ctx)
      self.stream.write(".")
      print(name)

    case .function:
      let ctx = node.children[0]
      let name = node.children[1]
      let type = node.children[2]
      print(ctx)
      self.stream.write(".")
      print(name)
      print(type.children[0])
    case .argumentTuple:
      print(node.children[0])

    case .type:
      print(node.children[0])

    case .bottomType:
      self.stream.write("_")

    case .functionType:
      let params = node.children[0]
      let retTy = node.children[1]
      self.stream.write("(")
      print(params)
      if !params.children.isEmpty {
        self.stream.write(", ")
      }
      self.stream.write("(")
      print(retTy)
      self.stream.write(") -> _")
      self.stream.write(")")

    case .tuple:
      printChildren(node.children, separator: ", ")
    case .tupleElement:
      let type = node.children[0]
      print(type)
    case .emptyTuple:
      self.stream.write("()")
    default:
      fatalError("\(node.kind)")
    }
  }

  func printChildren(_ children: [Demangler.Node], separator: String = "") {
    guard let last = children.last else {
      return
    }
    for child in children.dropLast() {
      print(child)
      stream.write(separator)
    }
    print(last)
  }
}
