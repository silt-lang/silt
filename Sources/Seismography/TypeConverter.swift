/// TypeConverter.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho
import Mantle

/// A `TypeConverter` is responsible for deciding the initial lowered
/// representation of a TT term.
///
/// - Note: At GIRGen time the exact layout of types is not fixed in the
///         representation to allow the Inner Core leeway.
public final class TypeConverter {
  public weak var module: GIRModule?
  private let tc: TypeChecker<CheckPhaseState>

  var wildcardName: Name {
    return Name(name: SyntaxFactory.makeUnderscore(presence: .implicit))
  }

  /// A `Lowering` describes extended type information used by GIRGen when
  /// interacting with lowered values.
  public class Lowering {
    enum Status {
      case incomplete(name: QualifiedName)
      case complete(type: GIRType, trivial: Bool, addressOnly: Bool)
    }

    public var isComplete: Bool {
      switch self.status {
      case .complete(type: _, trivial: _, addressOnly: _):
        return true
      default:
        return false
      }
    }

    public var name: QualifiedName {
      switch self.status {
      case let .incomplete(name: name):
        return name
      default:
        fatalError()
      }
    }

    /// The canonicalized lowered type.
    public var type: GIRType {
      switch self.status {
      case let .complete(type: ty, trivial: _, addressOnly: _):
        return ty
      default:
        fatalError("Incomplete lowering!")
      }
    }
    /// A trivial type is a loadable type with trivial value semantics - they
    /// may be loaded and stored without semantic copy or destroy operations.
    public var trivial: Bool {
      switch self.status {
      case let .complete(type: _, trivial: tr, addressOnly: _):
        return tr
      default:
        fatalError("Incomplete lowering!")
      }
    }
    /// An address-only type is a non-loadable value whose underlying
    /// representation is opaque.  It does not make sense to load from the
    /// address carried by values of this type, hence it is "Address Only".
    public var addressOnly: Bool {
      switch self.status {
      case let .complete(type: _, trivial: _, addressOnly: ao):
        return ao
      default:
        fatalError("Incomplete lowering!")
      }
    }

    private var status: Status

    init(name: QualifiedName) {
      self.status = .incomplete(name: name)
    }

    init(type: GIRType, isTrivial: Bool, isAddressOnly: Bool) {
      self.status = .complete(type: type, trivial: isTrivial,
                              addressOnly: isAddressOnly)
    }

    private func complete(type: GIRType, isTrivial: Bool, isAddressOnly: Bool) {
      self.status = .complete(type: type, trivial: isTrivial,
                              addressOnly: isAddressOnly)
    }

    func completeTrivial(type: GIRType) -> Lowering {
      self.complete(type: type, isTrivial: true, isAddressOnly: false)
      return self
    }

    func completeNonTrivial(type: GIRType) -> Lowering {
      self.complete(type: type, isTrivial: false, isAddressOnly: false)
      return self
    }

    func completeTrivialAddressOnly(type: GIRType) -> Lowering {
      self.complete(type: type, isTrivial: true, isAddressOnly: true)
      return self
    }

    func completeAddressOnly(type: GIRType) -> Lowering {
      self.complete(type: type, isTrivial: false, isAddressOnly: true)
      return self
    }
  }

  private struct CacheKey: Hashable {
    fileprivate enum Constant {
      case star
      case archetype
    }

    private enum Details: Hashable {
      case meta(Meta)
      case nominal(String)
      case constructorPayload(String)
      case loweredType(GIRType)
      case constant(Constant)
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

    init(constant: Constant) {
      self.details = .constant(constant)
    }

    static func == (lhs: CacheKey, rhs: CacheKey) -> Bool {
      return lhs.details == rhs.details
    }

    func hash(into hasher: inout Hasher) {
      self.details.hash(into: &hasher)
    }
  }

  /// Defines an area where types are registered as they are being lowered.
  /// This is necessary so recursive types can hit a base case and use their
  /// existing, incomplete GIR definition.
  private var loweringCache = [CacheKey: Lowering]()
  private var nominalKeyCache = [QualifiedName: CacheKey]()

  public init(_ tc: TypeChecker<CheckPhaseState>) {
    self.tc = tc
    self.prepopulateCache()
  }

  /// Retrieves the type lowering for a TT-type.
  public func lowerType(_ type: Type<TT>) -> Lowering {
    let key = self.getTypeKey(type)
    if let existing = self.loweringCache[key] {
      return existing
    }

    let resolvedType = self.resolveMetaIfNeeded(type)
    let resolvedKey = self.getTypeKey(resolvedType)
    if let existing = self.loweringCache[resolvedKey] {
      return existing
    }

    if case .pi(_, _) = resolvedType {
      let (env, end) = self.tc.unrollPi(resolvedType)
      let info = self.lower(end, in: .init(env))
      return info
    } else {
      let info = self.lower(type, in: .init([]))
      self.loweringCache[key] = info
      self.loweringCache[resolvedKey] = info
      self.loweringCache[CacheKey(loweredType: info.type)] = info
      return info
    }
  }

  /// Retrieves the lowering information for a previously-lowered type.
  ///
  /// This resolves outer boxed types to their underlying lowering.
  public func lowerType(_ type: GIRType) -> Lowering {
    if let arch = type as? ArchetypeType {
      return Lowering(name: QualifiedName()).completeAddressOnly(type: arch)
    }

    let cacheKey = CacheKey(loweredType: type)
    guard let existing = self.loweringCache[cacheKey] else {
      fatalError("Lowering referencing uncached type? \(type)")
    }
    return existing
  }

  public func getPayloadTypeOfConstructor(
    _ con: Opened<QualifiedName, TT>
  ) -> GIRType {
    let cacheKey = CacheKey(payloadOf: con.key.string)
    let conType = self.getASTTypeOfConstructor(con)
    guard case .pi(_, _) = conType else {
      return TupleType(elements: [], category: .object)
    }
    return self.withCachedKey(cacheKey, { _, lowering in
      self.completeDataConstructorPayloadType(con.key, conType,
                                              .init([]), lowering)
    }).type
  }

  private func getTypeKey(_ type: Type<TT>) -> CacheKey {
    switch type {
    case .refl: fatalError()
    case .type:
      return CacheKey(constant: .star)
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
      case let .variable(v):
        return CacheKey(name: v.name.description)
      }
    case .equal(_, _, _): fatalError()
    case .lambda(_): fatalError()
    case .pi(_, _): fatalError()
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

  private func prepopulateCache() {
    let starLowering = Lowering(name: QualifiedName())
      .completeTrivialAddressOnly(type: TypeType.shared)
    self.loweringCache[CacheKey(loweredType: TypeType.shared)] = starLowering
    self.loweringCache[CacheKey(constant: .star)] = starLowering
  }
}

extension TypeConverter {
  private func lower(_ type: Type<TT>, in env: Environment) -> Lowering {
    switch type {
    case .refl: fatalError("FIXME: Emit metadata here")
    case .type:
      return self.loweringCache[CacheKey(constant: .star)]!
    case .constructor(_, _):
      fatalError("Constructor forms should not appear here")
    case let .apply(head, elims):
      switch head {
      case let .definition(dd):
        let (_, openTypeDef) = self.tc.getOpenedDefinition(dd.key)
        let defTy = self.tc.getTypeOfOpenedDefinition(openTypeDef)
        let origType = self.resolveMetaIfNeeded(defTy)
        switch openTypeDef {
        case let .constant(_, const):
          switch const {
          case let .data(cons):
            return self.withCachedKey(dd.key) { dataTypeName, lowering in
              self.completeDataType(dataTypeName, origType, type, elims,
                                    cons, lowering)
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
        return self.lower(bind.body, in: env)
      case .variable(_):
        fatalError()
      }
    case .equal(_, _, _):
      fatalError("FIXME: Emit metadata here")
    case .lambda(_):
      fatalError("FIXME: Emit metadata here")
    case .pi(_, _):
      fatalError("FIXME: Emit metadata here")
    }
  }

  // swiftlint:disable function_parameter_count
  private func completeDataType(
    _ name: QualifiedName,
    _ origType: Type<TT>, _ substType: Type<TT>, _ elims: [Elim<TT>],
    _ constructors: [Opened<QualifiedName, TT>],
    _ lowering: Lowering
  ) {
    if completeDataTypeAsTrivialNat(name, substType, constructors, lowering) {
      return
    }

    var indices = Context()
    var curTy = origType
    while case let .pi(indexTy, next) = curTy {
      indices.append((wildcardName, indexTy))
      curTy = next
    }
    let environment = Environment(indices)

    var hasOnlyTrivialCons = true
    var loweredConstructors = [DataType.Constructor]()
    loweredConstructors.reserveCapacity(constructors.count)
    for constructor in constructors {
      let conName = constructor.key.string
      let conType = self.getASTTypeOfConstructor(constructor)
      switch conType {
      case .pi(_, _):
        let payloadLowering = Lowering(name: constructor.key)
        self.completeDataConstructorPayloadType(constructor.key, conType,
                                                environment, payloadLowering)
        hasOnlyTrivialCons = hasOnlyTrivialCons && payloadLowering.trivial
        loweredConstructors.append((conName, payloadLowering.type))
      default:
        loweredConstructors.append((conName, nil))
      }
    }

    let loweredIndices: GIRType
    switch origType {
    case .pi(_, _):
      let payloadLowering = Lowering(name: QualifiedName())
      self.completeDataConstructorPayloadType(name, origType,
                                              .init([]), payloadLowering)
      loweredIndices = payloadLowering.type
    default:
      loweredIndices = TypeType.shared
    }

    if hasOnlyTrivialCons {
      let lowType = self.module!.dataType(name: name,
                                              module: self.module,
                                              indices: loweredIndices,
                                              category: .object)
      let lowerKey = CacheKey(loweredType: lowType)
      lowType.addConstructors(loweredConstructors)
      self.loweringCache[lowerKey] = lowering.completeTrivial(type: lowType)
      return
    } else {
      let lowType = self.module!.dataType(name: name,
                                              module: self.module,
                                              indices: loweredIndices,
                                              category: .object)
      let lowerKey = CacheKey(loweredType: lowType)
      lowType.addConstructors(loweredConstructors)
      self.loweringCache[lowerKey] = lowering.completeNonTrivial(type: lowType)
      return
    }
  }

  fileprivate func completeDataConstructorPayloadType(
    _ name: QualifiedName,
    _ ty: Type<TT>,
    _ env: Environment,
    _ completing: Lowering
  ) {
    guard case .pi(_, _) = ty else {
      fatalError("Must lower an arrow type")
    }
    let (tel, _) = self.tc.unrollPi(ty)
    var hasOnlyTrivialElements = true
    var forceBox = false
    var eltTypes = [GIRType]()
    eltTypes.reserveCapacity(tel.count)
    for (idx, (_, type)) in tel.enumerated() {
      // swiftlint:disable force_try
      let substTy = try! type.applySubstitution(.strengthen(idx),
                                                tc.eliminate(_:_:))
      let eltLowering = self.lower(substTy, in: env)
      hasOnlyTrivialElements = hasOnlyTrivialElements
        && eltLowering.isComplete && eltLowering.trivial
      forceBox = forceBox || !eltLowering.isComplete
      guard eltLowering.isComplete else {
        let seedType = self.module!.dataType(name: eltLowering.name,
                                             module: self.module,
                                             indices: nil,
                                             category: .object)
        eltTypes.append(seedType)
        continue
      }
      eltTypes.append(eltLowering.type)
    }
    let payloadKey = name.string
    if forceBox {
      let ty = BoxType(TupleType(elements: eltTypes, category: .object))
      let lowering = completing.completeNonTrivial(type: ty)
      self.loweringCache[CacheKey(loweredType: ty)] = lowering
      self.loweringCache[CacheKey(payloadOf: payloadKey)] = lowering
    } else if hasOnlyTrivialElements {
      let ty = TupleType(elements: eltTypes, category: .object)
      let lowering = completing.completeTrivial(type: ty)
      self.loweringCache[CacheKey(loweredType: ty)] = lowering
      self.loweringCache[CacheKey(payloadOf: payloadKey)] = lowering
    } else {
      let ty = TupleType(elements: eltTypes, category: .object)
      let lowering = completing.completeNonTrivial(type: ty)
      self.loweringCache[CacheKey(loweredType: ty)] = lowering
      self.loweringCache[CacheKey(payloadOf: payloadKey)] = lowering
    }
  }

  private func completeDataTypeAsTrivialNat(
    _ name: QualifiedName, _ origType: Type<TT>,
    _ constructors: [Opened<QualifiedName, TT>],
    _ completing: Lowering
    ) -> Bool {
    guard constructors.count == 2 else {
      return false
    }

    let oneCon = constructors[0]
    let oneConTy = self.getASTTypeOfConstructor(oneCon)
    let twoCon = constructors[1]
    let twoConTy = self.getASTTypeOfConstructor(twoCon)

    func lowerNat(_ succ: String, _ zero: String, _ into: Lowering) -> Bool {
      let loweredType = self.module!.natType(name: name,
                                             zero: zero,
                                             succ: succ,
                                             module: self.module,
                                             category: .object)
      let payloadTy = TupleType(elements: [ loweredType ], category: .object)
      let lowering = into.completeTrivial(type: loweredType)
      let loweredPayload = Lowering(name: name).completeTrivial(type: payloadTy)
      self.loweringCache[CacheKey(loweredType: loweredType)] = lowering
      self.loweringCache[CacheKey(payloadOf: succ)] = loweredPayload
      return true
    }

    switch (oneConTy, twoConTy) {
    case (.pi(origType, _), origType):
      return lowerNat(oneCon.key.string, twoCon.key.string, completing)
    case (origType, .pi(origType, _)):
      return lowerNat(twoCon.key.string, oneCon.key.string, completing)
    default:
      return false
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
    _ name: QualifiedName, _ f: (QualifiedName, Lowering) -> Void) -> Lowering {
    let key = CacheKey(name: name.string)
    if let existing = self.loweringCache[key] {
      return existing
    }

    let low = Lowering(name: name)
    self.loweringCache[key] = low
    _ = f(name, low)
    return low
  }

  private func withCachedKey(
    _ key: CacheKey, _ f: (CacheKey, Lowering) -> Void) -> Lowering {
    if let existing = self.loweringCache[key] {
      return existing
    }

    let low = Lowering(name: QualifiedName())
    self.loweringCache[key] = low
    _ = f(key, low)
    return low
  }
}
