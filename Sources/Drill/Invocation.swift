/// Invocation.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere
import Crust

extension Diagnostic.Message {
    static let noInputFiles = Diagnostic.Message(.error, "no input files provided")
}

public struct Invocation {
    public let options: Options
    public let sourceFiles: [String]

    public init(options: Options, paths: [String]) {
        self.options = options
        self.sourceFiles = paths
    }

    public func run() throws {
        let engine = DiagnosticEngine()
        let consumer = PrintingDiagnosticConsumer(stream: &stderrStream)
        engine.register(consumer)

        if sourceFiles.isEmpty {
            engine.diagnose(.noInputFiles)
            return
        }

        for path in sourceFiles {
            let url = URL(fileURLWithPath: path)
            let contents = try String(contentsOf: url, encoding: .utf8)
            let lexer = Lexer(input: contents, filePath: path)
            let tokens = lexer.tokenize()
            switch options.mode {
            case .describeTokens:
                TokenDescriber.describe(tokens)
            case .reprint:
                let newTokens = tokens.map { token -> TokenSyntax in
                    if case .identifier(let text) = token.tokenKind {
                        return token.withTokenKind(.identifier("\(text)_garbo"))
                    }
                    return token
                }
                print(newTokens.map { $0.sourceText }.joined())
            }
        }
    }
}
