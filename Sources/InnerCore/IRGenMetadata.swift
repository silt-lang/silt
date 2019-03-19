/// IRGenMetadata.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Seismography
import LLVM

extension IRGenFunction {
  func emitTypeMetadataRefForLayout(_ T: GIRType) -> IRValue {
    return IGM.getOrCreateTypeMetadata(T)
  }
}

extension IRGenModule {
  /// Fetch the declaration of the metadata (or metadata template) for a
  /// type.
  ///
  /// If the definition type is specified, the result will always be a
  /// GlobalValue of the given type, which may not be at the
  /// canonical address point for a type metadata.
  ///
  /// If the definition type is not specified, then:
  ///   - if the metadata is indirect, then the result will not be adjusted
  ///     and it will have the type pointer-to-T, where T is the type
  ///     of a direct metadata
  ///   - if the metadata is a pattern, then the result will not be
  ///     adjusted and it will have FullTypeMetadataPtrTy
  ///   - otherwise it will be adjusted to the canonical address point
  ///     for a type metadata and it will have type TypeMetadataPtrTy.
  func getOrCreateTypeMetadata(_ concreteType: GIRType) -> IRConstant {
    var mangler = GIRMangler()
    concreteType.mangle(into: &mangler)
    mangler.append("N")
    let addr = self.getOrCreateGlobalVariable(mangler.finalize(),
                                              self.fullTypeMetadataStructTy)
    return addr.constGEP(indices: [
      IntType.int32.zero(),       // (*Self)
      IntType.int32.constant(1),  // .metadata
    ])
  }
}

extension IRGenModule {
  func addressOfBoxDescriptor(for BoxedType: GIRType) -> IRConstant {
    // FIXME: Work out what goes here.
    return PointerType.toVoid.constPointerNull()
  }
}
