/// Generic.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

public final class GenericEnvironment {
  public struct Key {
    let depth: UInt
    let index: UInt

    public init(depth: UInt, index: UInt) {
      self.depth = depth
      self.index = index
    }
  }

  let signature: GenericSignature

  public init(signature: GenericSignature) {
    self.signature = signature
  }

  public func find(_ k: Key) -> ArchetypeType? {
    return self.signature.archetypes[Int(k.index)]
  }
}

public final class GenericSignature {
  let archetypes: [ArchetypeType]

  public init(archetypes: [ArchetypeType]) {
    self.archetypes = archetypes
  }
}
