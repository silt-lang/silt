/// IRGenerator.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import LLVM
import OuterCore
import Seismography

public enum IRGen {
  public static func emit(_ module: GIRModule) -> Module {
    let igm = IRGenModule(module: module)
    igm.emit()
    igm.emitMain()
    return igm.module
  }
}

extension IRBuilder {
  func getOrCreateIntrinsic(
    _ name: String, _ signature: LLVM.FunctionType
  ) -> Function {
    if let intrinsic = self.module.function(named: name) {
      return intrinsic
    }
    return self.addFunction(name, type: signature)
  }

  @discardableResult
  func createLifetimeStart(
    _ buf: Address, _ size: Size = Size(bits: UInt64.max)
  ) -> Call {
    let argTys: [IRType] = [IntType.int64, PointerType.toVoid]
    let sig = LLVM.FunctionType(argTypes: argTys, returnType: VoidType())
    let fn = self.getOrCreateIntrinsic("llvm.lifetime.start.p0i8", sig)
    let addr: Address
    if buf.address.type.asLLVM() == PointerType.toVoid.asLLVM() {
      addr = buf
    } else {
      addr = self.createPointerBitCast(of: buf, to: PointerType.toVoid)
    }
    return self.buildCall(fn, args: [
      IntType.int64.constant(size.rawValue),
      addr.address,
    ])
  }

  @discardableResult
  func createLifetimeEnd(
    _ buf: Address, _ size: Size = Size(bits: UInt64.max)
  ) -> Call {
    let argTys: [IRType] = [IntType.int64, PointerType.toVoid]
    let sig = LLVM.FunctionType(argTypes: argTys, returnType: VoidType())
    let fn = self.getOrCreateIntrinsic("llvm.lifetime.end.p0i8", sig)
    let addr: Address
    if buf.address.type.asLLVM() == PointerType.toVoid.asLLVM() {
      addr = buf
    } else {
      addr = self.createPointerBitCast(of: buf, to: PointerType.toVoid)
    }
    return self.buildCall(fn, args: [
      IntType.int64.constant(size.rawValue),
      addr.address
    ])
  }
}

extension IRBuilder {
  func createAlloca(
    _ type: IRType, count: IRValue? = nil,
    alignment: Alignment, name: String = ""
  ) -> Address {
    let alloca = self.buildAlloca(type: type, count: count,
                                  alignment: alignment, name: name)
    return Address(alloca, alignment)
  }

  func createPointerBitCast(
    of address: Address, to type: PointerType
  ) -> Address {
    let addr = self.buildBitCast(address.address, type: type)
    return Address(addr, address.alignment)
  }

  func createElementBitCast(
    _ address: Address, _ type: IRType, name: String
  ) -> Address {
    guard let origPtrType = address.address.type as? PointerType else {
      fatalError()
    }
    if origPtrType.pointee.asLLVM() == type.asLLVM() {
      return address
    }
    let ptrType = PointerType(pointee: type)
    return self.createPointerBitCast(of: address, to: ptrType)
  }

  func createStructGEP(_ address: Address, _ index: Int,
                       _ layout: LLVM.StructLayout, _ name: String) -> Address {
    let offset = layout.memberOffsets[index]
    let addr = self.buildStructGEP(address.address, index: index,
                                   name: address.address.name + name)
    return Address(addr, address.alignment.alignment(at: offset))
  }

  func createStructGEP(_ address: Address, _ index: Int,
                       _ offset: Size, _ name: String) -> Address {
    let addr = self.buildStructGEP(address.address, index: index,
                                   name: address.address.name + name)
    return Address(addr, address.alignment.alignment(at: offset))
  }

  func createBitOrPointerCast(_ value: IRValue, to destTy: IRType,
                              _ name: String = "") -> IRValue {
    if value.type.asLLVM() == destTy.asLLVM() {
      return value
    }

    if value.type is PointerType, let destIntTy = destTy as? IntType {
      return self.buildPtrToInt(value, type: destIntTy, name: name)
    }

    if value.type is IntType, let destPtrTy = destTy as? PointerType {
      return self.buildIntToPtr(value, type: destPtrTy, name: name)
    }

    return self.buildBitCast(value, type: destTy, name: name)
  }
}
