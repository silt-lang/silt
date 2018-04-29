/// TypeConverter.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Moho
import Mantle
import Foundation

/// A `TypeConverter` is responsible for deciding the initial lowered
/// representation of a TT term.
///
/// - Note: At GIRGen time the exact layout of types is not fixed in the
///         representation to allow the Inner Core leeway.
public final class TypeConverter {
  public weak var module: GIRModule?
  private let tc: TypeChecker<CheckPhaseState>

  /// A `Lowering` describes extended type information used by GIRGen when
  /// interacting with lowered values.
  public class Lowering {
    /// The canonicalized lowered type.
    public let type: GIRType
    /// A trivial type is a loadable type with trivial value semantics - they
    /// may be loaded and stored without semantic copy or destroy operations.
    public let trivial: Bool
    /// An address-only type is a non-loadable value whose underlying
    /// representation is opaque.  It does not make sense to load from the
    /// address carried by values of this type, hence it is "Address Only".
    public let addressOnly: Bool

    init(type: GIRType, isTrivial: Bool, isAddressOnly: Bool) {
      self.type = type
      self.trivial = isTrivial
      self.addressOnly = isAddressOnly
    }
  }

  private struct CacheKey: Hashable {
    private enum Details: Hashable {
      case meta(Meta)
      case nominal(String)
      case constructorPayload(String)
      case loweredType(GIRType)
    }
    private let details: Details

    init(meta: Meta) {
      self.details = .meta(meta)
    }

    init(name: String) {
      self.details = .nominal(name)
    }

    init(payloadOf name: String) {
      self.details = .constructorPayload(name)
    }

    init(loweredType ty: GIRType) {
      self.details = .loweredType(ty)
    }

    static func == (lhs: CacheKey, rhs: CacheKey) -> Bool {
      return lhs.details == rhs.details
    }

    var hashValue: Int {
      return self.details.hashValue
    }
  }

  /// Defines an area where types are registered as they are being lowered.
  /// This is necessary so recursive types can hit a base case and use their
  /// existing, incomplete GIR definition.
  private var inProgressLowerings = Set<String>()
  private var loweringCache = [CacheKey: Lowering]()
  private var nominalKeyCache = [QualifiedName: CacheKey]()

  public init(_ tc: TypeChecker<CheckPhaseState>) {
    self.tc = tc
  }

  /// Retrieves the type lowering for a TT-type.
  public func lowerType(_ type: Type<TT>) -> Lowering {
    let key = self.getTypeKey(type)

    if let existing = self.loweringCache[key] {
      return existing
    }

    let resolvedKey = self.getTypeKey(self.resolveMetaIfNeeded(type))
    if let existing = self.loweringCache[resolvedKey] {
      return existing
    }

    let info = self.lower(type)
    self.loweringCache[key] = info
    self.loweringCache[resolvedKey] = info
    self.loweringCache[CacheKey(loweredType: info.type)] = info
    return info
  }

  /// Retrieves the lowering information for a previously-lowered type.
  ///
  /// This resolves outer boxed types to their underlying lowering.
  public func lowerType(_ type: GIRType) -> Lowering {
    guard let boxType = type as? BoxType else {
      let cacheKey = CacheKey(loweredType: type)
      guard let existing = self.loweringCache[cacheKey] else {
        fatalError("Lowering referencing uncached type? \(type)")
      }
      return existing
    }

    let cacheKey = CacheKey(name: boxType.payloadTypeName)
    guard let existing = self.loweringCache[cacheKey] else {
      fatalError("Formed box referencing uncached type? \(boxType)")
    }
    return existing
  }

  public func getPayloadTypeOfConstructor(
    _ con: Opened<QualifiedName, TT>
  ) -> GIRType {
    let cacheKey = CacheKey(payloadOf: con.key.string)
    if let existing = self.loweringCache[cacheKey] {
      return existing.type
    }
    let conType = self.getASTTypeOfConstructor(con)
    guard case .pi(_, _) = conType else {
      return TupleType(elements: [], category: .object)
    }
    return self.lowerDataConstructorPayloadType(con.key.string, conType).1
  }

  private func getTypeKey(_ type: Type<TT>) -> CacheKey {
    switch type {
    case .refl: fatalError()
    case .type: fatalError()
    case let .constructor(name, _):
      return CacheKey(name: name.key.string)
    case let .apply(head, _):
      switch head {
      case let .definition(dd):
        if let existingKey = self.nominalKeyCache[dd.key] {
          return existingKey
        }
        let newKey = CacheKey(name: dd.key.string)
        self.nominalKeyCache[dd.key] = newKey
        return newKey
      case let .meta(mv):
        return CacheKey(meta: mv)
      case .variable(_): fatalError()
      }
    case .equal(_, _, _): fatalError()
    case .lambda(_): fatalError()
    }
  }

  private func resolveMetaIfNeeded(_ t: Type<TT>) -> Type<TT> {
    switch t {
    case let .apply(head, _):
      switch head {
      case let .meta(mv):
        guard let bind = tc.signature.lookupMetaBinding(mv) else {
          fatalError()
        }
        return bind.body
      default:
        return t
      }
    default:
      return t
    }
  }
}

extension TypeConverter {
  private func lower(_ type: Type<TT>) -> Lowering {
    switch type {
    case .refl: fatalError("FIXME: Emit metadata here")
    case .type: fatalError("FIXME: Emit metadata here")
    case .constructor(_, _):
      fatalError("Constructor forms should not appear here")
    case let .apply(head, _):
      switch head {
      case let .definition(dd):
        let (_, openTypeDef) = self.tc.getOpenedDefinition(dd.key)
        switch openTypeDef {
        case let .constant(origType, const):
          switch const {
          case let .data(cons):
            return self.withCachedKey(dd.key.string) { dataTypeName in
              return self.visitDataType(dataTypeName, origType, type, cons)
            }
          case .function(_):
            fatalError("FIXME: Lower function applies")
          case .postulate:
            fatalError("FIXME: Emit metadata here")
          case .record(_, _):
            fatalError("FIXME: Treat records appropriately")
          }
        case .dataConstructor(_, _, _):
          fatalError("FIXME: Emit metadata here")
        case .module(_):
          fatalError("FIXME: Emit metadata here")
        case .projection(_, _, _):
          fatalError("FIXME: Treat records appropriately")
        }
      case let .meta(mv):
        guard let bind = tc.signature.lookupMetaBinding(mv) else {
          fatalError("Unbound meta!?")
        }
        return self.lower(bind.body)
      case .variable(_): fatalError()
      }
    case .equal(_, _, _):
      fatalError("FIXME: Emit metadata here")
    case .lambda(_):
      fatalError("FIXME: Emit metadata here")
    }
  }

  private func visitDataType(
    _ name: String,
    _ origType: Type<TT>, _ substType: Type<TT>,
    _ constructors: [Opened<QualifiedName, TT>]
  ) -> Lowering {
    var hasOnlyTrivialCons = true
    var forceAddressOnly = false
    var loweredConstructors = [DataType.Constructor]()
    loweredConstructors.reserveCapacity(constructors.count)
    for constructor in constructors {
      let conName = constructor.key.string
      let conType = self.getASTTypeOfConstructor(constructor)
      switch conType {
      case .pi(_, _):
        let (payloadLowering, loweredTy)
          = self.lowerDataConstructorPayloadType(conName, conType)
        hasOnlyTrivialCons = hasOnlyTrivialCons && payloadLowering.trivial
        forceAddressOnly = forceAddressOnly || payloadLowering.addressOnly
        loweredConstructors.append((conName, loweredTy))
      default:
        loweredConstructors.append((conName, nil))
      }
    }
    if forceAddressOnly {
      let loweredType = self.module!.dataType(name: name,
                                              category: .address)
      loweredType.addConstructors(loweredConstructors)
      return AddressOnlyLowering(loweredType)
    } else if hasOnlyTrivialCons {
      let loweredType = self.module!.dataType(name: name,
                                              category: .object)
      loweredType.addConstructors(loweredConstructors)
      return TrivialLowering(loweredType)
    } else {
      let loweredType = self.module!.dataType(name: name,
                                              category: .object)
      loweredType.addConstructors(loweredConstructors)
      return NonTrivialLowering(loweredType)
    }
  }

  fileprivate func lowerDataConstructorPayloadType(
    _ name: String,
    _ ty: Type<TT>
  ) -> (Lowering, TupleType) {
    guard case .pi(_, _) = ty else {
      fatalError("Must lower an arrow type")
    }
    let (tel, _) = self.tc.unrollPi(ty)
    var hasOnlyTrivialElements = true
    var forceAddressOnly = false
    var eltTypes = [GIRType]()
    eltTypes.reserveCapacity(tel.count)
    for (_, type) in tel {
      let eltLowering = self.lower(type)
      hasOnlyTrivialElements = hasOnlyTrivialElements && eltLowering.trivial
      forceAddressOnly = forceAddressOnly || eltLowering.addressOnly
      eltTypes.append(eltLowering.type)
    }
    if forceAddressOnly {
      let ty = TupleType(elements: eltTypes, category: .address)
      let lowering = AddressOnlyLowering(ty)
      self.loweringCache[CacheKey(loweredType: ty)] = lowering
      self.loweringCache[CacheKey(payloadOf: name)] = lowering
      return (lowering, ty)
    } else if hasOnlyTrivialElements {
      let ty = TupleType(elements: eltTypes, category: .object)
      let lowering = TrivialLowering(ty)
      self.loweringCache[CacheKey(loweredType: ty)] = lowering
      self.loweringCache[CacheKey(payloadOf: name)] = lowering
      return (lowering, ty)
    } else {
      let ty = TupleType(elements: eltTypes, category: .object)
      let lowering = NonTrivialLowering(ty)
      self.loweringCache[CacheKey(loweredType: ty)] = lowering
      self.loweringCache[CacheKey(payloadOf: name)] = lowering
      return (lowering, ty)
    }
  }

  private func getASTTypeOfConstructor(
    _ name: Opened<QualifiedName, TT>) -> Type<TT> {
    guard let def = self.tc.signature.lookupDefinition(name.key) else {
      fatalError("Name \(name) does not correspond to opened definition?")
    }
    guard case let .dataConstructor(_, _, ty) = def.inside else {
      fatalError("Name \(name) does not correspond to opened data constructor?")
    }

    return self.resolveMetaIfNeeded(ty.inside)
  }

  private func withCachedKey(
    _ key: String, _ f: (String) -> Lowering) -> Lowering {
    guard !self.inProgressLowerings.contains(key) else {
      return RecursiveLowering(key)
    }

    self.inProgressLowerings.insert(key)
    let result = f(key)
    self.inProgressLowerings.remove(key)
    return result
  }
}

private class RecursiveLowering: TypeConverter.Lowering {
  init(_ name: String) {
    super.init(type: BoxType(name),
               isTrivial: false, isAddressOnly: false)
  }
}

private class TrivialLowering: TypeConverter.Lowering {
  init(_ type: GIRType) {
    super.init(type: type, isTrivial: true, isAddressOnly: false)
  }
}

private class NonTrivialLowering: TypeConverter.Lowering {
  init(_ type: GIRType) {
    super.init(type: type, isTrivial: false, isAddressOnly: false)
  }
}

private class AddressOnlyLowering: TypeConverter.Lowering {
  init(_ type: GIRType) {
    super.init(type: type, isTrivial: false, isAddressOnly: true)
  }
}
