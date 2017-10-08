import Yaml
import CommandLineKit
import Foundation

extension OutputStream: TextOutputStream {
  public func write(_ string: String) {
    let data = string.data(using: .utf8)!
    _ = data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) in
      write(ptr, maxLength: data.count)
    }
  }
}

enum LoadError: Error {
  case invalidYAML(path: String)
}

func loadSyntax(path: String) throws -> [Node] {
  let url = URL(fileURLWithPath: path)
  let file = try String(contentsOf: url)
  let obj = try Yaml.load(file)
  guard case let .dictionary(dict) = obj else {
    throw LoadError.invalidYAML(path: path)
  }
  return dict.map { Node(name: $0.key.string!, props: $0.value.dictionary!) }
}

func loadTokens(path: String) throws -> [Token] {
  let url = URL(fileURLWithPath: path)
  let file = try String(contentsOf: url)
  let obj = try! Yaml.load(file)
  guard case let .dictionary(dict) = obj else {
    throw LoadError.invalidYAML(path: path)
  }
  return dict.map { Token(name: "\($0.key.string!)Token", props: $0.value.dictionary!) }
}

enum OutputKind: String {
  case syntaxKind
  case structs
  case tokenKind
  case batch
}

let cli = CommandLineKit.CommandLine()
let nodesPath = StringOption(longFlag: "nodes-yaml",
                             required: true,
                             helpMessage: "The path to the YAML file containing the node specifications.")
let tokensPath = StringOption(longFlag: "tokens-yaml",
                              required: true,
                              helpMessage: "The path to the YAML file containing the token specifications.")
let emissionKind = EnumOption<OutputKind>(longFlag: "kind",
                                          required: true,
                                          helpMessage: "The kind of file you're emitting.")
let outputPath = StringOption(shortFlag: "o",
                              longFlag: "output-dir",
                              required: true,
                              helpMessage: "The output directory.")

cli.addOptions(nodesPath, tokensPath, emissionKind, outputPath)

do {
  try cli.parse()
} catch {
  cli.printUsage()
  exit(EXIT_FAILURE)
}

do {
  let nodes = try loadSyntax(path: nodesPath.value!)
  let tokens = try loadTokens(path: tokensPath.value!)
  let generator = try SwiftGenerator(outputDir: outputPath.value!,
                                     nodes: nodes,
                                     tokens: tokens)
  generator.generate(emissionKind.value!)
} catch {
  print("error: \(error)")
}
