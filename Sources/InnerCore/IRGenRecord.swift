/// IRGenRecord.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import LLVM
import Seismography
import OuterCore
import Mantle

struct RecordField {
  let layout: FieldLayout

  func projectAddress(_ IGF: IRGenFunction, _ seq: Address,
                      _ offsets: DynamicOffsets? = nil) -> Address {
    return self.layout.project(IGF, seq, "", offsets)
  }

  var fixedByteOffset: Size {
    return self.layout.byteOffset
  }

  var isEmpty: Bool {
    return self.layout.isEmpty
  }

  var isPOD: Bool {
    return self.layout.isPOD
  }
}

final class LoadableRecordTypeInfo: LoadableTypeInfo {
  let fixedSize: Size
  let llvmType: IRType
  let fixedAlignment: Alignment
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
      guard let loadableTI = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      loadableTI.copy(IGF, src, dest)
    }
  }

  func consume(_ IGF: IRGenFunction, _ explosion: Explosion) {
    for field in self.fields {
      guard let loadableTI = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      loadableTI.consume(IGF, explosion)
    }
  }

  func packIntoPayload(_ IGF: IRGenFunction, _ payload: Payload,
                       _ source: Explosion, _ startOffset: Size) {
    for field in self.fields {
      guard !field.isEmpty else {
        continue
      }

      guard let loadableTI = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      let offset = field.fixedByteOffset + startOffset
      loadableTI.packIntoPayload(IGF, payload, source, offset)
    }
  }

  func unpackFromPayload(_ IGF: IRGenFunction, _ payload: Payload,
                         _ destination: Explosion, _ startOffset: Size) {
    for field in self.fields {
      guard !field.isEmpty else {
        continue
      }
      guard let loadableTI = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      let offset = field.fixedByteOffset + startOffset
      loadableTI.unpackFromPayload(IGF, payload, destination, offset)
    }
  }

  var isKnownEmpty: Bool {
    return self.fixedSize == .zero
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
      guard let loadableTI = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      loadableTI.buildAggregateLowering(IGM, builder, fieldOffset)
    }
  }

  func reexplode(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Explosion) {
    for field in fields {
      guard let loadableTI = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      loadableTI.reexplode(IGF, src, dest)
    }
  }

  func initialize(_ IGF: IRGenFunction, _ from: Explosion, _ addr: Address) {
    for field in fields {
      if field.isEmpty {
        continue
      }

      guard let loadableTI = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      let fieldAddr = field.projectAddress(IGF, addr)
      loadableTI.initialize(IGF, from, fieldAddr)
    }
  }

  func loadAsCopy(_ IGF: IRGenFunction, _ addr: Address, _ out: Explosion) {
    for field in fields {
      if field.isEmpty {
        continue
      }

      guard let loadableTI = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }
      let fieldAddr = field.projectAddress(IGF, addr)
      loadableTI.loadAsCopy(IGF, fieldAddr, out)
    }
  }

  func loadAsTake(_ IGF: IRGenFunction, _ addr: Address, _ out: Explosion) {
    for field in fields {
      if field.isEmpty {
        continue
      }

      guard let loadableTI = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }

      let fieldAddr = field.projectAddress(IGF, addr)
      loadableTI.loadAsTake(IGF, fieldAddr, out)
    }
  }

  func assign(_ IGF: IRGenFunction, _ src: Explosion, _ dest: Address) {
    for field in fields {
      if field.isEmpty {
        continue
      }

      guard let loadableTI = field.layout.typeInfo as? LoadableTypeInfo else {
        fatalError()
      }

      loadableTI.assign(IGF, src, dest)
    }
  }

  func buildExplosionSchema(_ schema: Explosion.Schema.Builder) {
    for field in fields {
      field.layout.typeInfo.buildExplosionSchema(schema)
    }
  }
}

final class FixedRecordTypeInfo: FixedTypeInfo, IndirectTypeInfo {
  let llvmType: IRType
  let fixedSize: Size
  let fixedAlignment: Alignment
  let fields: [RecordField]

  init(_ fields: [RecordField],
       _ storageStype: IRType, _ size: Size, _ align: Alignment) {
    self.fields = fields
    self.llvmType = storageStype
    self.fixedAlignment = align
    self.fixedSize = size
  }

  var isKnownEmpty: Bool {
    return self.fixedSize == .zero
  }

  func destroy(_ IGF: IRGenFunction, _ addr: Address, _ type: GIRType) {
    IGF.GR.emitDestroyCall(type, addr)
  }

  func assignWithCopy(_ IGF: IRGenFunction,
                      _ dest: Address, _ src: Address, _ type: GIRType) {
    IGF.GR.emitAssignWithCopyCall(type, dest, src)
  }
}

final class NonFixedRecordTypeInfo: WitnessSizedTypeInfo {
  let llvmType: IRType
  let alignment: Alignment
  let fields: [RecordField]

  init(_ fields: [RecordField], _ storageStype: IRType, _ align: Alignment) {
    self.fields = fields
    self.llvmType = storageStype
    self.alignment = align
  }
}
