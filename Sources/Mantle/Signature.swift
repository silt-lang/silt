/// Signature.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Moho
import Lithosphere

/// The Signature keeps track of global entities needed during the type checking
/// process.
public final class Signature {
  private var definitions: [QualifiedName: ContextualDefinition] = [:]
  private var metaTypes: [Meta: Type<TT>] = [:]
  private var metaBindings: [Meta: Meta.Binding] = [:]
  private var metaSources: [Meta: Expr] = [:]
  private var metasCount: Int = 1

  public init() {}

  private func addDefinition(
    _ key: QualifiedName, _ def: ContextualDefinition) {
    guard self.definitions[key] == nil else {
      fatalError()
    }
    self.definitions[key] = def
  }

  private func replaceDefinition(
    _ key: QualifiedName, _ def: ContextualDefinition) {
    guard self.definitions[key] != nil else {
      fatalError()
    }
    self.definitions[key] = def
  }
}

extension Signature {
  func addMeta(_ type: Type<TT>, from syntax: Expr?) -> Meta {
    defer { self.metasCount += 1 }
    let mv = Meta(self.metasCount)
    self.metaTypes[mv] = type
    if let syntax = syntax {
      self.metaSources[mv] = syntax
    }
    return mv
  }

  func addModule(
    _ mod: Module, named name: QualifiedName, args: Telescope<TT>) {
    return self.addDefinition(name,
                              ContextualDefinition(telescope: args,
                                                   inside: .module(mod)))
  }

  func addData(
    named name: QualifiedName, _ tel: Telescope<TT>, _ type: Type<TT>) {
    let cdef = ContextualDefinition(telescope: tel,
                                    inside: .constant(type, .data([])))
    return self.addDefinition(name, cdef)
  }

  func addRecord(
    named name: QualifiedName, _ tel: Telescope<TT>, _ type: Type<TT>) {
    let cdef = ContextualDefinition(telescope: tel,
                                    inside: .constant(type, .record(name, [])))
    return self.addDefinition(name, cdef)
  }

  func addConstructor(
    named dataCon: QualifiedName,
    toType dataName: Opened<QualifiedName, TT>,
    _ numArgs: UInt,
    _ type: ContextualType
  ) {
    let dataKey = dataName.key
    let def = self.lookupDefinition(dataKey)!
    switch def.inside {
    case let .constant(tyConType, .data(existingCons)):
      self.addDefinition(dataCon,
                         ContextualDefinition(telescope: def.telescope,
                                              inside: .dataConstructor(dataKey,
                                                                       numArgs,
                                                                       type)))
      // FIXME: Good god, this is inefficient.
      let moreCons = existingCons + [dataCon]
      self.definitions[dataKey]
        = ContextualDefinition(telescope: def.telescope,
                               inside: .constant(tyConType, .data(moreCons)))
    case .constant(_, .record(_, _)):
      self.addDefinition(dataCon,
                         ContextualDefinition(telescope: def.telescope,
                                              inside: .dataConstructor(dataKey,
                                                                       numArgs,
                                                                       type)))
    default:
      fatalError()
    }
  }

  func addProjection(
    named projName: QualifiedName,
    index projIx: Projection.Field,
    parent parentRec: Opened<QualifiedName, TT>,
    _ recType: ContextualType
  ) {
    let def = self.lookupDefinition(parentRec.key)!
    switch def.inside {
    case let .constant(tyConType, .record(recName, existingProjs)):
      // FIXME: Good god, this is inefficient.
      let moreProj = existingProjs + [Projection(name: projName, field: projIx)]
      self.definitions[parentRec.key]
        = ContextualDefinition(telescope: def.telescope,
                               inside: .constant(tyConType, .record(recName,
                                                                    moreProj)))
    default:
      fatalError()
    }
  }

  func addPostulate(
    named name: QualifiedName, _ tel: Telescope<TT>, _ type: Type<TT>) {
    self.addDefinition(name,
                       ContextualDefinition(telescope: tel,
                                            inside: .constant(type,
                                                              .postulate)))
  }

  func addAscription(
    named name: QualifiedName, _ tel: Telescope<TT>, _ type: Type<TT>) {
    let newDef: Definition = .constant(type, .function(.open))
    self.addDefinition(name,
                       ContextualDefinition(telescope: tel,
                                            inside: newDef))
  }

  func addFunctionClauses(
    _ name: Opened<QualifiedName, TT>, _ inv: Instantiability.Invertibility) {
    let def = self.lookupDefinition(name.key)!
    guard case let .constant(ty, .function(.open)) = def.inside else {
      fatalError()
    }

    let newDef: Definition = .constant(ty, .function(.invertible(inv)))
    self.replaceDefinition(name.key,
                           ContextualDefinition(telescope: def.telescope,
                                                inside: newDef))
  }

  @available(*, deprecated, message: "Only for use in the debugger!")
  func dumpMetas() {
    for (mv, mb) in self.metaBindings {
      print(mv, ":", self.metaTypes[mv]!.description)
      print(mv, ":=", mb.internalize.description,
            "[ from", self.metaSources[mv]!.description, "]")
    }
  }
}

extension Signature {
  func instantiateMeta(_ mv: Meta, _ mvb: Meta.Binding) {
    guard self.metaTypes[mv] != nil else {
      fatalError()
    }
    self.metaBindings[mv] = mvb
  }
}

extension Signature {
  func lookupMetaBinding(_ mv: Meta) -> Meta.Binding? {
    return self.metaBindings[mv]
  }

  func lookupMetaType(_ mv: Meta) -> TT? {
    return self.metaTypes[mv]
  }

  func lookupDefinition(_ name: QualifiedName) -> ContextualDefinition? {
    return self.definitions[name]
  }
}
