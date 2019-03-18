/// IRGenType.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography
import LLVM
import PrettyStackTrace

final class TypeConverter {
  let IGM: IRGenModule
  private let cache: TypeCache

  final class TypeCache {
    enum Entry {
      case typeInfo(TypeInfo)
      case llvmType(IRType)
    }
    fileprivate var cache: [GIRType: Entry] = [:]
    fileprivate var paramConventionCache: [GIRType: NativeConvention] = [:]
    fileprivate var returnConventionCache: [GIRType: NativeConvention] = [:]
  }

  init(_ IGM: IRGenModule) {
    self.cache = TypeCache()
    self.IGM = IGM
  }

  func parameterConvention(for T: GIRType) -> NativeConvention {
    if let cacheHit = self.cache.paramConventionCache[T] {
      return cacheHit
    }

    let ti = self.getCompleteTypeInfo(T)
    let conv = NativeConvention(self.IGM, ti, false)
    self.cache.paramConventionCache[T] = conv
    return conv
  }

  func returnConvention(for T: GIRType) -> NativeConvention {
    if let cacheHit = self.cache.returnConventionCache[T] {
      return cacheHit
    }

    let ti = self.getCompleteTypeInfo(T)
    let conv = NativeConvention(self.IGM, ti, true)
    self.cache.paramConventionCache[T] = conv
    return conv
  }

  func getCompleteTypeInfo(_ T: GIRType) -> TypeInfo {
    guard case let .typeInfo(entry) = getTypeEntry(T) else {
      fatalError("getting TypeInfo recursively!")
    }
    return entry
  }

  private func convertType(_ T: GIRType) -> TypeCache.Entry {
    switch T {
    case let type as DataType:
      return self.convertDataType(type)
//    case let type as RecordType:
//      return self.visitRecordType(type)
    case let type as ArchetypeType:
      return self.convertArchetypeType(type)
    case let type as SubstitutedType:
      return self.convertSubstitutedType(type)
    case let type as Seismography.FunctionType:
      return self.convertFunctionType(type)
//    case let type as TypeMetadataType:
//      return self.visitTypeMetadataType(type)
    case let type as TypeType:
      return self.convertTypeToMetadata(type)
    case let type as BottomType:
      return self.convertBottomType(type)
//    case let type as GIRExprType:
//      return self.visitGIRExprType(type)
    case let type as TupleType:
      return self.convertTupleType(type)
    case let type as BoxType:
      return self.convertBoxType(type)
    default:
      fatalError("attempt to convert unknown type \(T)")
    }
  }

  private func getTypeEntry(_ T: GIRType) -> TypeCache.Entry {
    if let cacheHit = self.cache.cache[T] {
      return cacheHit
    }

    // Convert the type.
    let convertedEntry = convertType(T)
    guard case .typeInfo(_) = convertedEntry else {
      // If that gives us a forward declaration (which can happen with
      // bound generic types), don't propagate that into the cache here,
      // because we won't know how to clear it later.
      return convertedEntry
    }

    // Cache the entry under the original type and the exemplar type, so that
    // we can avoid relowering equivalent types.
    if let existing = self.cache.cache[T], case .typeInfo(_) = existing {
      fatalError("")
    }
    self.cache.cache[T] = convertedEntry

    return convertedEntry
  }
}

extension TypeConverter {
  func convertArchetypeType(_ type: ArchetypeType) -> TypeCache.Entry {
    return .typeInfo(OpaqueArchetypeTypeInfo(self.IGM.opaquePtrTy.pointee))
  }
}

extension TypeConverter {
  func convertBottomType(_ type: BottomType) -> TypeCache.Entry {
    return .typeInfo(EmptyTypeInfo(IntType.int8))
  }
}

extension TypeConverter {
  func convertTypeToMetadata(_ type: TypeType) -> TypeCache.Entry {
    return .typeInfo(EmptyTypeInfo(IntType.int8))
  }
}

extension TypeConverter {
  func convertSubstitutedType(_ type: SubstitutedType) -> TypeCache.Entry {
    return self.convertType(type.substitutee)
  }
}

extension TypeConverter {
  func convertDataType(_ type: DataType) -> TypeCache.Entry {
    let storageType = self.createNominalType(IGM, type)

    // Create a forward declaration for that type.
    self.addForwardDecl(type, storageType)

    // Determine the implementation strategy.
    let strategy = self.IGM.strategize(self, type, storageType)

    return .typeInfo(strategy.typeInfo())
  }

  private func addForwardDecl(_ key: GIRType, _ type: IRType) {
    self.cache.cache[key] = .llvmType(type)
  }

  private func createNominalType(_ IGM: IRGenModule,
                                 _ type: DataType) -> StructType {
    var mangler = GIRMangler()
    mangler.append("T")
    type.mangle(into: &mangler)
    return IGM.B.createStruct(name: mangler.finalize())
  }
}

extension TypeConverter {
  func convertTupleType(_ type: TupleType) -> TypeCache.Entry {
    var fieldTypesForLayout = [TypeInfo]()
    fieldTypesForLayout.reserveCapacity(type.elements.count)

    var loadable = true

    var explosionSize = 0
    for astField in type.elements {
      // Compute the field's type info.
      let fieldTI = IGM.getTypeInfo(astField)
      fieldTypesForLayout.append(fieldTI)

      guard let loadableFieldTI = fieldTI as? LoadableTypeInfo else {
        loadable = false
        continue
      }

      explosionSize += loadableFieldTI.explosionSize()
    }

    // Perform layout and fill in the fields.
    let layout = RecordLayout(.nonHeapObject, self.IGM,
                              type.elements, fieldTypesForLayout)
    let fields = layout.fieldLayouts.map { RecordField(layout: $0) }
    if loadable {
      return .typeInfo(LoadableTupleTypeInfo(fields, explosionSize,
                                             layout.llvmType,
                                             layout.minimumSize,
                                             layout.minimumAlignment))
    } else if layout.wantsFixedLayout {
      return .typeInfo(FixedTupleTypeInfo(fields, layout.llvmType,
                                          layout.minimumSize,
                                          layout.minimumAlignment))
    } else {
      return .typeInfo(NonFixedTupleTypeInfo(fields, layout.llvmType,
                                             layout.minimumAlignment))
    }
  }
}

extension TypeConverter {
  func convertBoxType(_ T: BoxType) -> TypeCache.Entry {
    // We can share a type info for all dynamic-sized heap metadata.
    let UT = T.underlyingType
    let eltTI = self.IGM.getTypeInfo(UT)
    guard let fixedTI = eltTI as? FixedTypeInfo else {
      return .typeInfo(NonFixedBoxTypeInfo(IGM))
    }

    // For fixed-sized types, we can emit concrete box metadata.
    if fixedTI.isKnownEmpty {
      return .typeInfo(EmptyBoxTypeInfo(IGM))
    }

    return .typeInfo(FixedBoxTypeInfo(IGM, T.underlyingType))
  }
}

extension TypeConverter {
  func convertFunctionType(_ T: Seismography.FunctionType) -> TypeCache.Entry {
    return .typeInfo(FunctionTypeInfo(self.IGM, T, PointerType.toVoid,
                                      self.IGM.getPointerSize(),
                                      self.IGM.getPointerAlignment()))
  }
}
