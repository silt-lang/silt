public class SyntaxDumper<StreamType: TextOutputStream> {
  var stream: StreamType
  var indent = 0

  public init(stream: inout StreamType) {
    self.stream = stream
  }

  public func withIndent(_ f: () -> Void) {
    indent += 2
    f()
    indent -= 2
  }

  public func write(_ string: String) {
    stream.write(String(repeating: " ", count: indent))
    stream.write(string)
  }

  public func line(_ string: String = "") {
    write(string)
    stream.write("\n")
  }

  public func dump(_ node: Syntax, root: Bool = true) {
    switch node {
    case let node as TokenSyntax:
      write("(token .\(node.tokenKind))")
    default:
      write("(\(node.kind)")
      withIndent {
        for child in node.children {
          line()
          dump(child, root: false)
        }
      }
      stream.write(")")
    }
    if root { line() }
  }
}
