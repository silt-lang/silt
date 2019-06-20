/// IRGenModule.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import cllvm
import LLVM
import Seismography
import OuterCore
import PrettyStackTrace

final class IRGenModule {
  let B: IRBuilder
  let girModule: GIRModule
  let module: Module
  var mangler = GIRMangler()
  lazy var typeConverter: TypeConverter = TypeConverter(self)
  let dataLayout: TargetData

  var stringsForTypeRef = [String: (IRGlobal, IRConstant)]()

  let sizeTy: IntType
  let typeMetadataStructTy: StructType
  let typeMetadataPtrTy: PointerType
  let refCountedTy: StructType
  let refCountedPtrTy: PointerType
  let opaquePtrTy: PointerType
  let fullTypeMetadataStructTy: StructType
  let fullTypeMetadataPtrTy: PointerType
  let tupleTypeMetadataTy: StructType
  let tupleTypeMetadataPtrTy: PointerType
  let witnessTablePtrTy: PointerType

  private(set) var scopeMap = [OuterCore.Scope: IRGenFunction]()

  init(module: GIRModule) {
    initializeLLVM()

    LLVMInstallFatalErrorHandler { msg in
      let str = String(cString: msg!)
      print(str)
      exit(EXIT_FAILURE)
    }
    self.girModule = module
    self.module = Module(name: girModule.name)

    self.B = IRBuilder(module: self.module)
    self.dataLayout = self.module.dataLayout

    self.sizeTy = self.dataLayout.intPointerType(context: self.module.context)

    self.typeMetadataStructTy = self.B.createStruct(name: "swift.type", types: [
      self.sizeTy
    ], isPacked: false)
    self.typeMetadataPtrTy = PointerType(pointee: self.typeMetadataStructTy,
                                         addressSpace: 0)

    self.refCountedTy = self.B.createStruct(name: "silt.refcounted", types: [
      self.typeMetadataPtrTy,
      self.sizeTy,
    ], isPacked: false)
    self.refCountedPtrTy =
      PointerType(pointee: self.refCountedTy, addressSpace: 0)
    self.opaquePtrTy =
      PointerType(pointee: self.B.createStruct(name: "silt.opaque"))
    self.witnessTablePtrTy = PointerType(pointee: PointerType.toVoid)
    self.fullTypeMetadataStructTy = self.B.createStruct(name: "silt.full_type",
                                                        types: [
      self.witnessTablePtrTy,
      self.typeMetadataStructTy,
    ])
    self.fullTypeMetadataPtrTy =
      PointerType(pointee: self.fullTypeMetadataStructTy)
    // A tuple type metadata record has a couple extra fields.
    let tupleElementTy = self.B.createStruct(name: "silt.tuple_element_type",
                                             types: [
      self.typeMetadataPtrTy,      // Metadata *Type
      self.sizeTy                  // size_t Offset
    ])
    self.tupleTypeMetadataTy = self.B.createStruct(name: "silt.tuple_type", types: [
      self.typeMetadataStructTy,                        // (base)
      self.sizeTy,                                      // size_t NumElements
      PointerType.toVoid,                               // const char *Labels
      ArrayType(elementType: tupleElementTy, count: 0), // Element Elements[]
    ])
    self.tupleTypeMetadataPtrTy = PointerType(pointee: self.tupleTypeMetadataTy)
  }

  func getTypeInfo(_ ty: GIRType) -> TypeInfo {
    return self.typeConverter.getCompleteTypeInfo(ty)
  }

  func emit() {
    trace("emitting LLVM IR for module '\(girModule.name)'") {
      for scope in girModule.topLevelScopes {
        let igf = IRGenGIRFunction(irGenModule: self, scope: scope)
        igf.emitBody()
      }
    }
  }

  func emitMain() {
    let fn = B.addFunction("main", type: FunctionType([], IntType.int32))
    let entry = fn.appendBasicBlock(named: "entry")
    B.positionAtEnd(of: entry)
    B.buildRet(0 as Int32)
  }
}

extension IRGenModule {
  func getPointerSize() -> Size {
    return self.module.dataLayout.pointerSize()
  }

  func getPointerAlignment() -> Alignment {
    // We always use the pointer's width as its swift ABI alignment.
    return Alignment(UInt32(self.getPointerSize().rawValue))
  }

  func getSize(_ size: Size) -> IRValue {
    let szTy = self.dataLayout.intPointerType()
    return szTy.constant(size.rawValue)
  }
}

extension IRGenModule {
  func function(for f: Continuation) -> (Function, LLVM.FunctionType) {
    // swiftlint:disable force_cast
    let signature = LoweredSignature(self, f.type as! Seismography.FunctionType)
    let key = self.mangler.mangle(f)
    if let fn = self.module.function(named: key) {
      return (fn, signature.type)
    }

    return (self.B.addFunction(key, type: signature.type), signature.type)
  }
}
