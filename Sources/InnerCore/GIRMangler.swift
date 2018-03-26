/// GIRMangler.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Seismography
import OuterCore

public struct GIRMangler {
  let punycoder = Punycode()

  public init() {}

  func prefix(_ isTopLevel: Bool) -> String {
    return isTopLevel ? "_S" : ""
  }

  /// Mangles a Silt identifier, punycode-encoding if necessary.
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

  public func mangle(_ module: GIRModule) -> String {
    return "\(prefix(true))\(mangleIdentifier(module.name))"
  }

  public func mangle(_ dataType: DataType,
                     isTopLevel: Bool = false) -> String {
    return "\(prefix(isTopLevel))D\(mangleIdentifier(dataType.name))"
  }

  public func mangle(_ recordType: RecordType,
                     isTopLevel: Bool = false) -> String {
    return "\(prefix(isTopLevel))R\(mangleIdentifier(recordType.name))"
  }

  public func mangle(_ continuation: Continuation) -> String {
    return "\(prefix(true))C\(mangleIdentifier(continuation.name))"
  }
}
