/// IRValueWitnessTable.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import LLVM
import Seismography

enum ValueWitnessFunction {
  case destroy
}

enum ValueWitnessValue {
  case size
}

extension IRGenRuntime {
  func emitValueWitnessFunctionRef(
    _ type: GIRType, _ vwf: ValueWitnessFunction) -> (LLVM.Function, IRValue) {
    fatalError()
  }

  func emitValueWitnessValue(
    _ type: GIRType, _ index: ValueWitnessValue) -> IRValue {
    fatalError()
  }
}

extension IRGenRuntime {
  func emitLoadOfSize(_ T: GIRType) -> IRValue {
    return self.emitValueWitnessValue(T, .size)
  }

  func emitUnmanagedAlloc(
    _ layout: RecordLayout, _ captureDescriptor: IRConstant
  ) -> IRValue {
    let metadata = layout.getPrivateMetadata(IGF.IGM, captureDescriptor)
    let size = layout.emitSize(IGF.IGM)
    let alignMask = layout.emitAlignMask(IGF.IGM)

    return self.emitAlloc(metadata, size, alignMask)
  }

  func emitDestroyCall(_ T: GIRType, _ object: Address) {
    guard !T.type.isTrivial(self.IGF.IGM.girModule) else {
      return
    }

    let (fn, metadata) = self.emitValueWitnessFunctionRef(T, .destroy)
    let ptrTy = self.IGF.IGM.opaquePtrTy
    let objectPtr = self.IGF.B.createPointerBitCast(of: object, to: ptrTy)
    _ = self.IGF.B.buildCall(fn, args: [objectPtr.address, metadata])
  }

  func emitAssignWithCopyCall(_ T: GIRType,
                              _ destObject: Address, _ srcObject: Address) {
    fatalError("Unimplemented")
  }

  func emitAssignWithTakeCall(_ T: GIRType,
                              _ destObject: Address, _ srcObject: Address) {
    fatalError("Unimplemented")
  }
}
