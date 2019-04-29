/// IRGenDataType.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import LLVM
import Seismography
import OuterCore
import Mantle

/// A type that open-codes an implementation for a particular class of
/// data type.
///
/// A `DataTypeStrategy` is the high-level interface to manipulate values of
/// a particular data type.  It provides a way to query the runtime layout
/// of its type, functions to operate on values at runtime, and the
/// implementation of a `switch` operation.
///
/// In general, a data type consists of a discriminator value and optional
/// payload values.  In the most abstract case, this implies a data type value
/// is laid out as at least two independent values in memory. However, there are
/// many opportunities available to optimize this layout and thus optimize and
/// simplify the code we need to construct and destructure these values.
///
/// `DataTypeStrategy` should generally not be implemented directly.  Prefer to
/// implement `NoPayloadStrategy` or `PayloadStrategy`.
protocol DataTypeStrategy: Assignable, Loadable, Aggregable,
                           Explodable, Destroyable, Cohabitable {
  /// The layout planner for this data type.
  var planner: DataTypeLayoutPlanner { get }

  /// Emit the construction sequence for a data value into an explosion.
  /// This implements the 'data_init' instruction.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - selector: The selector of the constructor that is being built.
  ///   - data: An explosion containing the data values used to construct the
  ///     payload for this data value.
  ///   - destination: The destination explosion containing the
  ///     freshly-constructed data type value.
  func emitDataInjection(_ IGF: IRGenFunction, _ selector: String,
                         _ data: Explosion, _ destination: Explosion)

  /// Emit the destruction sequence for a data value by extracting the
  /// discriminator value and using it to branch to a given corresponding block.
  ///
  /// A hypothetical implementation of an enum with a payload is to have the
  /// discriminator bits as the first value of the explosion, and the bitpattern
  /// for the payload itself as the remaining values.  In which case, the
  /// `switch_constr` operation will load the discriminator bits, then pass
  /// the partially-consumed explosion to this function where the remaining
  /// values will be re-projected into the destination explosion.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - source: An explosion containing the values needed to discriminate a
  ///     value of this data type.
  ///   - destinations: A map from enum case selectors to basic blocks.
  ///   - default: The basic block to branch to if no selector matches, if any.
  ///     If no default is provided, the implementation must synthesize a block
  ///     that terminates in an `unreachable` instruction.
  func emitSwitch(_ IGF: IRGenFunction, _ source: Explosion,
                  _ destinations: [(String, BasicBlock)],
                  _ default: BasicBlock?)

  /// Projects the payload value from an explosion of a given data type
  /// into a secondary explosion.  The values of that explosion are used to bind
  /// the parameters coming into the destination block of a `switch_constr`
  /// instruction for a particular constructor.
  ///
  /// A hypothetical implementation of an enum with a payload is to have the
  /// discriminator bits as the first value of the explosion, and the bitpattern
  /// for the payload itself as the remaining values.  In which case, the
  /// `switch_constr` operation will load the discriminator bits, then pass
  /// the partially-consumed explosion to this function where the remaining
  /// values will be re-projected into the destination explosion.
  ///
  /// - Parameters:
  ///   - IGF: The IR Builder for the current function.
  ///   - selector: The selector of the constructor that is being projected.
  ///   - source: The set of values available to reproject.
  ///   - destination: The destination explosion.  The values appended to this
  ///     explosion are used to bind the parameters of the destination block in
  ///     a `switch_constr` operation.
  func emitDataProjection(_ IGF: IRGenFunction, _ selector: String,
                          _ source: Explosion, _ destination: Explosion)
}

extension DataTypeStrategy {
  /// Retrieve the type info describing the layout of this strategy.
  ///
  /// - Returns: The type info for this strategy.
  func typeInfo() -> TypeInfo {
    return self.planner.completeTypeLayout(for: self)
  }

  /// Returns the index of a particular case within a data type declaration.
  ///
  /// This value is effectively a source-order index into a data type.  It may
  /// be used as a discriminator value.
  ///
  /// - Parameter selector: The selector for the case to look up the index for.
  /// - Returns: The index of the case for the given selector.
  func indexOf(selector: String) -> UInt64 {
    // FIXME: It's super lame that this is O(n).
    var tagIndex = 0 as UInt64
    for payload in self.planner.payloadElements {
      if payload.selector == selector {
        return tagIndex
      }
      tagIndex += 1
    }
    for payload in self.planner.noPayloadElements {
      if payload.selector == selector {
        return tagIndex
      }
      tagIndex += 1
    }
    fatalError("couldn't find case")
  }
}

/// A refinement of `DataTypeStrategy` for strategies without payload values.
protocol NoPayloadStrategy: DataTypeStrategy, SingleScalarizable {}

extension NoPayloadStrategy {
  static var isPOD: Bool {
    return true
  }

  func explosionSize() -> Int {
    return 1
  }

  func emitScalarRetain(_ IGF: IRGenFunction, _ value: IRValue) { }
  func emitScalarRelease(_ IGF: IRGenFunction, _ value: IRValue) { }

  func getDiscriminatorType() -> IntType {
    guard
      let structTy = self.typeInfo().llvmType as? StructType,
      let discrim = structTy.elementTypes[0] as? IntType
    else {
      fatalError()
    }
    return discrim
  }

  func discriminatorIndex(for tag: String) -> LLVM.Constant<Signed> {
    let index = self.planner.noPayloadElements.firstIndex(where: {
      $0.selector == tag
    })!
    return self.getDiscriminatorType().constant(index)
  }

  func emitSwitch(_ IGF: IRGenFunction, _ value: Explosion,
                  _ dests: [(String, BasicBlock)], _ def: BasicBlock?) {
    let discriminator = value.claimSingle()

    let defaultDest = def ?? {
      let defaultDest = IGF.function.appendBasicBlock(named: "")
      let pos = IGF.B.insertBlock!
      IGF.B.positionAtEnd(of: defaultDest)
      IGF.B.buildUnreachable()
      IGF.B.positionAtEnd(of: pos)
      return defaultDest
    }()

    switch dests.count {
    case 0:
      guard def != nil else {
        IGF.B.buildUnreachable()
        return
      }
      IGF.B.buildBr(defaultDest)
    case 1:
      let cmp = IGF.B.buildICmp(discriminator, IntType.int1.zero(), .notEqual)
      IGF.B.buildCondBr(condition: cmp, then: dests[0].1, else: defaultDest)
    case 2 where def == nil:
      let firstDest = dests[0]
      let nextDest = dests[1]
      let caseTag = self.discriminatorIndex(for: firstDest.0)
      let cmp = IGF.B.buildICmp(discriminator, caseTag, .notEqual)
      IGF.B.buildCondBr(condition: cmp, then: nextDest.1, else: firstDest.1)
      defaultDest.removeFromParent()
    default:
      let switchInst = IGF.B.buildSwitch(discriminator, else: defaultDest,
                                         caseCount: dests.count)
      for (name, dest) in dests {
        switchInst.addCase(discriminatorIndex(for: name), dest)
      }
    }
  }
}

protocol PayloadStrategy: DataTypeStrategy {
  var payloadSchema: Payload.Schema { get }
  var payloadElementCount: Int { get }
}

extension PayloadStrategy {
  func buildExplosionSchema(_ builder: Explosion.Schema.Builder) {
    switch self.planner.optimalTypeInfoKind {
    case .dynamic:
      builder.append(.aggregate(self.typeInfo().llvmType,
                                self.typeInfo().alignment))
    default:
      self.payloadSchema.forEachType(self.planner.IGM) { payloadTy in
        builder.append(.scalar(payloadTy))
      }
    }
  }

  func buildAggregateLowering(_ IGM: IRGenModule,
                              _ builder: AggregateLowering.Builder,
                              _ offset: Size) {
    var runningOffset = offset
    payloadSchema.forEachType(IGM) { payloadTy in
      let end = IGM.dataLayout.storeSize(of: payloadTy) + runningOffset
      builder.append(.concrete(type: payloadTy, begin: runningOffset, end: end))
      runningOffset += IGM.dataLayout.storeSize(of: payloadTy)
    }
  }

  func explosionSize() -> Int {
    return self.payloadElementCount
  }

  func getFixedPayloadTypeInfo() -> FixedTypeInfo & Cohabitable {
    switch self.planner.payloadElements[0] {
    case let .fixed(_, ti):
      return ti
    default:
      fatalError()
    }
  }

  func getLoadablePayloadTypeInfo() -> LoadableTypeInfo {
    switch self.planner.payloadElements[0] {
    case let .fixed(_, ti):
      // swiftlint:disable force_cast
      return ti as! LoadableTypeInfo
    default:
      fatalError()
    }
  }

  func reexplode(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    dest.append(contentsOf: src.claim(next: explosionSize()))
  }

  func copy(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    reexplode(IGF, src, dest)
  }

  func assign(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Address) {
    let destExplosion = Explosion()
    let maybeFixed = self as? FixedTypeInfo
    if let fixed = maybeFixed, !fixed.isPOD {
      self.loadAsTake(IGF, dest, destExplosion)
    }
    initialize(IGF, src, dest)
    if let fixed = maybeFixed, !fixed.isPOD {
      self.consume(IGF, destExplosion)
    }
  }

  func loadAsCopy(_ IGF: IRGenFunction,
                  _ addr: Address, _ explosion: Explosion) {
    let tmp = Explosion()
    loadAsTake(IGF, addr, tmp)
    copy(IGF, tmp, explosion)
  }
}

final class DataTypeLayoutPlanner {
  enum TypeInfoKind {
    case dynamic
    case fixed
    case loadable
  }

  enum Element {
    case dynamic(String)
    case fixed(String, FixedTypeInfo & Cohabitable)

    var selector: String {
      switch self {
      case let .dynamic(el):
        return el
      case let .fixed(el, _):
        return el
      }
    }
  }

  let IGM: IRGenModule
  let girType: DataType
  let llvmType: StructType
  let optimalTypeInfoKind: TypeInfoKind
  let payloadElements: [Element]
  let noPayloadElements: [Element]
  private var layout: TypeInfo?

  init(
    IGM: IRGenModule, girType: DataType, storageType: StructType,
    typeInfoKind: TypeInfoKind,
    withPayload: [Element], withoutPayload: [Element]
  ) {
    self.IGM = IGM
    self.girType = girType
    self.llvmType = storageType
    self.optimalTypeInfoKind = typeInfoKind
    self.payloadElements = withPayload
    self.noPayloadElements = withoutPayload
  }

  func completeTypeLayout(
    for strategy: DataTypeStrategy
  ) -> TypeInfo {
    return self.layout!
  }

  func fulfill(_ p: (DataTypeLayoutPlanner) -> TypeInfo) {
    precondition(self.layout == nil, "cannot re-layout plan!")
    self.layout = p(self)
  }
}
