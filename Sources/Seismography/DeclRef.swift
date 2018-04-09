/// DeclRef.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

public struct DeclRef: Hashable {
  public enum Kind: Int {
    case function = 0
    case dataConstructor = 1
  }
  public let name: String
  public let kind: Kind

  public init(_ name: String, _ kind: Kind) {
    self.name = name
    self.kind = kind
  }

  public static func == (lhs: DeclRef, rhs: DeclRef) -> Bool {
    return lhs.name == rhs.name && lhs.kind == rhs.kind
  }

  public var hashValue: Int {
    return 0x9e3779b9 &* self.name.hashValue &+ self.kind.rawValue
  }
}
