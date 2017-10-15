/// Generator.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Foundation

extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        write(string.data(using: .utf8)!)
    }
}

class SwiftGenerator {
  let outputDir: URL
  private var file: FileHandle?
  let tokenMap: [String: Token]
  var indentWidth = 0

  init(outputDir: String) throws {
    self.outputDir = URL(fileURLWithPath: outputDir)
    var tokenMap = [String: Token]()
    for token in tokenNodes {
      tokenMap[token.name + "Token"] = token
    }
    self.tokenMap = tokenMap
  }

  func write(_ string: String) {
    file?.write(string)
  }

  func line(_ string: String = "") {
    file?.write(String(repeating: " ", count: indentWidth))
    file?.write(string)
    file?.write("\n")
  }

  func currentYear() -> Int {
    return Calendar.current.component(.year, from: Date())
  }

  func writeHeaderComment(filename: String) {
    line("""
    /// \(filename)
    /// Automatically generated by SyntaxGen. Do not edit!
    ///
    /// Copyright \(currentYear()), The Silt Language Project.
    ///
    /// This project is released under the MIT license, a copy of which is
    /// available in the repository.
    """)
  }

  func generate() {
    generateSyntaxKindEnum()
    generateStructs()
    generateTokenKindEnum()
  }

  func startWriting(to filename: String) {
    let url = outputDir.appendingPathComponent(filename)
    if FileManager.default.fileExists(atPath: url.path) {
        try! FileManager.default.removeItem(at: url)
    }
    FileManager.default.createFile(atPath: url.path, contents: nil)
    file = try! FileHandle(forWritingTo: url)
    writeHeaderComment(filename: filename)
  }

  func generateTokenKindEnum() {
    startWriting(to: "TokenKind.swift")
    line("public enum TokenKind: Equatable {")
    line("  case eof")
    for (_, token) in tokenMap {
      write("  case \(token.caseName.asStandaloneIdentifier)")
      if case .associated(let type) = token.kind {
        write("(\(type))")
      }
      line()
    }
    line()
    line("  public init(punctuation: String) {")
    line("    switch punctuation {")
    for (_, token) in tokenMap {
      guard case .punctuation(let text) = token.kind else { continue }
      line("    case \"\(text)\": self = .\(token.caseName)")
    }
    line("    default: fatalError(\"Not punctuation?\")")
    line("    }")
    line("  }")
    line()
    line("  public init(identifier: String) {")
    line("    switch identifier {")
    for (_, token) in tokenMap {
      guard case .keyword(let text) = token.kind else { continue }
      line("    case \"\(text)\": self = .\(token.caseName)")
    }
    line("    default: self = .identifier(identifier)")
    line("    }")
    line("  }")
    line("  public var text: String {")
    line("    switch self {")
    line("    case .eof: return \"\"")
    for (_, token) in tokenMap {
      write("    case .\(token.caseName)")
      switch token.kind {
      case .associated(_):
        line("(let text): return text.description")
      case .keyword(let text), .punctuation(let text):
        line(": return \"\(text)\"")
      }
    }
    line("    }")
    line("  }")
    line("  public static func == (lhs: TokenKind, rhs: TokenKind) -> Bool {")
    line("    switch (lhs, rhs) {")
    line("    case (.eof, .eof): return true")
    for (_, token) in tokenMap {
      switch token.kind {
      case .associated(_):
        line("    case (.\(token.caseName)(let l), .\(token.caseName)(let r)): return l == r")
      case .keyword(_), .punctuation(_):
        line("    case (.\(token.caseName), .\(token.caseName)): return true")
      }
    }
    line("    default: return false")
    line("    }")
    line("  }")
    line("}")
  }

  func generateSyntaxKindEnum() {
    startWriting(to: "SyntaxKind.swift")
    line("public enum SyntaxKind {")
    line("  case token")
    line("  case unknown")
    for node in syntaxNodes {
      line("  case \(node.typeName.asStandaloneIdentifier)")
    }
    line("}")
    line()
    line("""
    extension Syntax {
      /// Creates a Syntax node from the provided RawSyntax using the appropriate
      /// Syntax type, as specified by its kind.
      /// - Parameters:
      ///   - raw: The raw syntax with which to create this node.
      ///   - root: The root of this tree, or `nil` if the new node is the root.
      static func fromRaw(_ raw: RawSyntax) -> Syntax {
        let data = SyntaxData(raw: raw)
        return make(root: nil, data: data)
      }

      /// Creates a Syntax node from the provided SyntaxData using the appropriate
      /// Syntax type, as specified by its kind.
      /// - Parameters:
      ///   - root: The root of this tree, or `nil` if the new node is the root.
      ///   - data: The data for this new node.
      static func make(root: SyntaxData?, data: SyntaxData) -> Syntax {
        let root = root ?? data
        switch data.raw.kind {
        case .token: return TokenSyntax(root: root, data: data)
        case .unknown: return Syntax(root: root, data: data)
    """)
    for node in syntaxNodes {
        line("    case .\(node.typeName.lowercaseFirstLetter):")
        line("      return \(node.typeName)Syntax(root: root, data: data)")
    }
    line("""
        }
      }
    }
    """)
  }

  func generateStructs() {
    startWriting(to: "SyntaxNodes.swift")
    line("""
      public class ExprSyntax: Syntax {}
      """)
    line("""
      public class DeclSyntax: Syntax {}
      """)
    for node in syntaxNodes {
      generateStruct(node)
    }
  }

  func makeMissing(child: Child) -> String {
    if child.isToken {
      guard let token = tokenMap[child.kind] else {
        fatalError("unknown token kind '\(child.kind)'")
      }
      return "RawSyntax.missingToken(.\(token.caseName))"
    } else {
      return "RawSyntax.missing(.\(child.kindCaseName))"
    }
  }

  func generateStruct(_ node: Node) {
    switch node.kind {
    case let .collection(element):
      let elementKind = element.contains("Token") ? "Token" : element
      line("public typealias \(node.typeName)Syntax = SyntaxCollection<\(elementKind)Syntax>")
      line()
    case let .node(kind, children):
      line("public class \(node.typeName)Syntax: \(kind)Syntax {")
      if !children.isEmpty {
        line("  public enum Cursor: Int {")
        for child in children {
          line("    case \(child.name.asStandaloneIdentifier)")
        }
        line("  }")
      }
      line()

      write("  public convenience init(")
      let childParams = children
        .map {
          let childKind = $0.isToken ? "Token" : $0.kind
          let optional = $0.isOptional ? "?" : ""
          return "\($0.name): \(childKind)Syntax\(optional)"
        }
        .joined(separator: ", ")
      write(childParams)
      line(") {")
      line("    let raw = RawSyntax.node(.\(node.typeName.lowercaseFirstLetter), [")
      for child in  children {
        if child.isOptional {
          line("      \(child.name)?.raw ?? \(makeMissing(child: child)),")
        } else {
          line("      \(child.name).raw,")
        }
      }
      line("    ], .present)")
      line("    let data = SyntaxData(raw: raw, indexInParent: 0, parent: nil)")
      line("    self.init(root: data, data: data)")
      line("  }")

      for child in  children {
        let childKind = child.kind.contains("Token") ? "Token" : child.kind
        let optional = child.isOptional ? "?" : ""
        let castKeyword = child.isOptional ? "as?" : "as!"
        line("""
            public var \(child.name): \(childKind)Syntax\(optional) {
              return child(at: Cursor.\(child.name)) \(castKeyword) \(childKind)Syntax
            }
            public func with\(child.name.uppercaseFirstLetter)(_ syntax: \(childKind)Syntax) -> \(node.typeName)Syntax {
              let (newRoot, newData) = data.replacingChild(syntax.raw, at: Cursor.\(child.name))
              return \(node.typeName)Syntax(root: newRoot, data: newData)
            }

          """)
      }
      line("}")
      line()
    }
  }
}
