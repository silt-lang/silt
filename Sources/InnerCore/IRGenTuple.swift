/// IRGenTuple.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography
import LLVM

/// Provides type information for a tuple of loadable values.
///
/// A tuple of loadable values is itself loadable.  All operations delegate
/// to the underlying loadable fields, and adjust member offsets accordingly.
final class LoadableTupleTypeInfo: TupleTypeInfo, LoadableTypeInfo {
  let llvmType: IRType
  let fixedSize: Size
  let fixedAlignment: Alignment

  var isKnownEmpty: Bool {
    return self.fixedSize == .zero
  }

  let fields: [RecordField]
  let staticExplosionSize: Int

  init(_ fields: [RecordField], _ explosionSize: Int,
       _ storageStype: IRType, _ size: Size, _ align: Alignment) {
    self.fields = fields
    self.staticExplosionSize = explosionSize
    self.llvmType = storageStype
    self.fixedSize = size
    self.fixedAlignment = align
  }

  func explosionSize() -> Int {
    return self.staticExplosionSize
  }

  func copy(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    for field in self.fields {
      guard let layout = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      layout.copy(IGF, src, dest)
    }
  }

  func consume(_ IGF: IRGenFunction, _ explosion: Explosion) {
    for field in self.fields {
      guard let layout = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      layout.consume(IGF, explosion)
    }
  }

  func packIntoPayload(_ IGF: IRGenFunction, _ payload: Payload,
                       _ source: Explosion, _ startOffset: Size) {
    for field in self.fields {
      guard !field.isEmpty else {
        continue
      }
      let offset = field.fixedByteOffset + startOffset
      guard let layout = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      layout.packIntoPayload(IGF, payload, source, offset)
    }
  }

  func unpackFromPayload(_ IGF: IRGenFunction, _ payload: Payload,
                         _ destination: Explosion, _ startOffset: Size) {
    for field in self.fields {
      guard !field.isEmpty else {
        continue
      }
      let offset = field.fixedByteOffset + startOffset
      guard let layout = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      layout.unpackFromPayload(IGF, payload, destination, offset)
    }
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) {
    return IGF.GR.emitDestroyCall(type, addr)
  }

  func assignWithCopy(_ IGF: IRGenFunction,
                      _ dest: Address, _ src: Address, _ type: GIRType) {
    return IGF.GR.emitAssignWithCopyCall(type, dest, src)
  }

  func buildAggregateLowering(_ IGM: IRGenModule,
                              _ builder: AggregateLowering.Builder,
                              _ offset: Size) {
    for field in self.fields {
      let fieldOffset = offset + field.fixedByteOffset
      guard let layout = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      layout.buildAggregateLowering(IGM, builder, fieldOffset)
    }
  }

  func reexplode(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    for field in fields {
      guard let layout = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      layout.reexplode(IGF, src, dest)
    }
  }

  func initialize(_ IGF: IRGenFunction, _ from: Explosion, _ addr: Address) {
    for field in fields {
      guard !field.isEmpty else {
        continue
      }

      let fieldAddr = field.projectAddress(IGF, addr)
      guard let layout = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      layout.initialize(IGF, from, fieldAddr)
    }
  }

  func assign(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Address) {
    for field in fields {
      guard !field.isEmpty else {
        continue
      }

      guard let layout = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      layout.assign(IGF, src, dest)
    }
  }

  func loadAsCopy(_ IGF: IRGenFunction, _ addr: Address, _ out: Explosion) {
    for field in fields {
      guard !field.isEmpty else {
        continue
      }

      let fieldAddr = field.projectAddress(IGF, addr)
      guard let layout = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      layout.loadAsCopy(IGF, fieldAddr, out)
    }
  }

  func loadAsTake(_ IGF: IRGenFunction, _ addr: Address, _ out: Explosion) {
    for field in fields {
      guard !field.isEmpty else {
        continue
      }

      let fieldAddr = field.projectAddress(IGF, addr)
      guard let layout = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      layout.loadAsTake(IGF, fieldAddr, out)
    }
  }

  func buildExplosionSchema(_ schema: Explosion.Schema.Builder) {
    for field in fields {
      field.layout.typeInfo.buildExplosionSchema(schema)
    }
  }
}

/// Provides type information for a tuple of fixed-size values.
///
/// A tuple of fixed-size values is itself a fixed-size value.
final class FixedTupleTypeInfo: TupleTypeInfo, FixedTypeInfo, IndirectTypeInfo {
  let llvmType: IRType
  let fixedSize: Size
  let fixedAlignment: Alignment
  let fields: [RecordField]

  var isKnownEmpty: Bool {
    return self.fixedSize == .zero
  }

  init(_ fields: [RecordField], _ storageStype: IRType,
       _ size: Size, _ align: Alignment) {
    self.fields = fields
    self.llvmType = storageStype
    self.fixedAlignment = align
    self.fixedSize = size
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) {
    guard let tupleTy = type as? TupleType else {
      fatalError()
    }
    for (idx, field) in self.fields.enumerated() {
      guard !field.isPOD else {
        continue
      }

      field.layout.typeInfo.destroy(IGF, field.projectAddress(IGF, addr),
                                    tupleTy.elements[idx])
    }
  }

  func assignWithCopy(_ IGF: IRGenFunction,
                      _ dest: Address, _ src: Address, _ type: GIRType) {
    guard let tupleTy = type as? TupleType else {
      fatalError()
    }
    for (idx, field) in self.fields.enumerated() {
      guard !field.isEmpty else {
        continue
      }

      let destField = field.projectAddress(IGF, dest)
      let srcField = field.projectAddress(IGF, src)
      field.layout.typeInfo.assignWithCopy(IGF, destField, srcField,
                                           tupleTy.elements[idx])
    }
  }
}

/// Provides type information for a tuple of runtime-sized values.
final class NonFixedTupleTypeInfo: TupleTypeInfo, WitnessSizedTypeInfo {
  let llvmType: IRType
  let alignment: Alignment
  let fields: [RecordField]

  init(_ fields: [RecordField], _ storageStype: IRType, _ align: Alignment) {
    self.fields = fields
    self.llvmType = storageStype
    self.alignment = align
  }

  func dynamicOffsets(_ IGF: IRGenFunction, _ T: GIRType) -> DynamicOffsets? {
    struct TupleNonFixedOffsets: DynamicOffsets {
      let type: GIRType

      func offsetForIndex(_ IGF: IRGenFunction, _ index: Int) -> IRValue {
        let metadata = IGF.emitTypeMetadataRefForLayout(self.type)
        let asTuple = IGF.B.buildBitCast(metadata,
                                         type: IGF.IGM.tupleTypeMetadataPtrTy)

        let slot = IGF.B.buildInBoundsGEP(asTuple, indices: [
          IGF.IGM.getSize(.zero),       // (*tupleType)
          IntType.int32.constant(3),    //   .Elements
          IGF.IGM.getSize(Size(index)), //     [index]
          IntType.int32.constant(1),    //       .Offset
        ])
        return IGF.B.buildLoad(slot, alignment: IGF.IGM.getPointerAlignment(),
                               name: metadata.name + ".\(index).offset")
      }
    }
    return TupleNonFixedOffsets(type: T)
  }
}
