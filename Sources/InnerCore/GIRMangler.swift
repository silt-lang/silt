/// GIRMangler.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import LLVM
import Seismography
import OuterCore

public struct GIRMangler {
  let punycoder = Punycode()
  public init() {}
  public func mangleIdentifier(_ identifier: String) -> String {
    let requiresPunycode = identifier.unicodeScalars.contains { !$0.isASCII }
    if requiresPunycode {
      guard let punycode = punycoder.encode(utf8String: identifier.utf8) else {
        fatalError("could not mangle \(identifier)")
      }
      return "X\(punycode.utf8.count)\(punycode)"
    }
    return "\(identifier.utf8.count)\(identifier)"
  }

  public func mangle(_ continuation: Continuation) -> String {
    return "C\(mangleIdentifier(continuation.name))"
  }
}
