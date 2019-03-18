/// Remangle.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public struct Remangler: Mangler {
  public init() {}

  /// The storage for the mangled symbol.
  private var buffer: Data = Data()

  /// Word substitutions in mangled identifiers.
  private var substitutionWordRanges: [Range<Data.Index>] = []

  /// A map of known substitutions to indices
  /// FIXME: Use nodes as keys.
  private var substitutions = [Demangler.Node.Kind: UInt]()

  public mutating func beginMangling() {
    self.buffer.removeAll()
    self.buffer.reserveCapacity(128)
    self.substitutionWordRanges.removeAll()
    self.buffer.append(MANGLING_PREFIX, count: MANGLING_PREFIX.count)
  }

  public func finalize() -> String {
    assert(!buffer.isEmpty, "Mangling an empty name")
    guard let result = String(data: self.buffer, encoding: .utf8) else {
      fatalError()
    }

    return result
  }

  public mutating func append(_ str: String) {
    self.buffer.append(str, count: str.count)
  }

  public mutating func mangleIdentifier(_ orig: String) {
    let sub = trySubstitution(.init(.identifier(orig)))
    mangleIdentifierImpl(orig,
                         &self.buffer, &self.substitutionWordRanges)
    _ = sub.map { addSubstitution($0) }
  }

  mutating func trySubstitution(_ node: Demangler.Node) -> Demangler.Node? {
    guard let idx = self.substitutions[node.kind] else {
      return nil
    }

    if idx >= 26 {
      self.buffer.append(ManglingScalars.UPPERCASE_A)
      mangleIndex(idx - 26)
      return node
    }
    return node
  }

  mutating func mangleIndex(_ value: UInt) {
    if value == 0 {
      self.buffer.append(ManglingScalars.DOLLARSIGN)
    } else {
      self.buffer.append("\(value - 1)", count: "\(value - 1)".count)
      self.buffer.append(ManglingScalars.DOLLARSIGN)
    }
  }

  mutating func addSubstitution(_ node: Demangler.Node) {
    let Idx = UInt(self.substitutions.count)
    self.substitutions[node.kind] = Idx
  }
}

extension Demangler.Node: ManglingEntity {
  public func mangle<M: Mangler>(into mangler: inout M) {
    switch self.kind {
    case .global:
      mangler.append(MANGLING_PREFIX)
      for child in self.children {
        child.mangle(into: &mangler)
      }

    case let .identifier(str):
      mangler.mangleIdentifier(str)
    case let .module(str):
      mangler.mangleIdentifier(str)

    case .data:
      self.children[0].mangle(into: &mangler)
      self.children[1].mangle(into: &mangler)
      mangler.append("D")

    case .function:
      self.children[0].mangle(into: &mangler)
      self.children[1].mangle(into: &mangler)
      self.children[2].mangle(into: &mangler)
      mangler.append("F")

    case .argumentTuple:
      let child = skipType(self.children[0])
      if child.kind == .tuple && child.children.isEmpty {
        mangler.append("y")
        return
      }
      child.mangle(into: &mangler)

    case .type:
      self.children[0].mangle(into: &mangler)

    case .typeType:
      mangler.append("T")

    case .functionType:
      for child in self.children.reversed() {
        child.mangle(into: &mangler)
      }
      mangler.append("f")
    case .bottomType:
      mangler.append("B")

    case .substitutedType:
      let ty = self.children[0]
      assert(ty.kind == .data)
      var isFirstListItem = true
      for child in self.children[1].children {
        child.mangle(into: &mangler)
        if isFirstListItem {
          isFirstListItem = false
        }
      }
      if isFirstListItem {
        mangler.append("y")
      }
      ty.mangle(into: &mangler)
      mangler.append("G")

    case .tuple:
      var isFirstListItem = true
      for child in self.children {
        child.mangle(into: &mangler)
        if isFirstListItem {
          mangler.append("_")
          isFirstListItem = false
        }
      }
      if isFirstListItem {
        mangler.append("y")
      }
      mangler.append("t")
    case .emptyTuple:
      mangler.append("y")
    case .tupleElement:
      self.children[0].mangle(into: &mangler)
    case .firstElementMarker:
      mangler.append("_")
    }
  }
}

func skipType(_ node: Demangler.Node) -> Demangler.Node {
  if node.kind == .type {
    return node.children[0]
  }
  return node
}
