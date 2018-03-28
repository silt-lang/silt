import LLVM

/// A set of known runtime intrinsic functions declared in the Ferrite headers.
enum RuntimeIntrinsic: String {
  /// The runtime hook for the  copy_value instruction.
  case copyValue = "silt_copyValue"

  /// The runtime hook for the destroy_value instruction.
  case destroyValue = "silt_destroyValue"

  /// The runtime hook for the silt alloc function.
  case alloc  = "silt_alloc"

  /// The runtime hook for the silt alloc function.
  case dealloc  = "silt_dealloc"

  /// The LLVM IR type corresponding to the definition of this function.
  var type: FunctionType {
    switch self {
    case .copyValue:
      return FunctionType(argTypes: [PointerType.toVoid],
                          returnType: PointerType.toVoid)
    case .destroyValue:
      return FunctionType(argTypes: [PointerType.toVoid],
                          returnType: VoidType())
    case .alloc:
      return FunctionType(argTypes: [IntType.int64],
                          returnType: PointerType.toVoid)
    case .dealloc:
      return FunctionType(argTypes: [PointerType.toVoid],
                          returnType: VoidType())
    }
  }
}

final class IRGenRuntime {
  unowned let IGF: IRGenFunction

  init(irGenFunction: IRGenFunction) {
    self.IGF = irGenFunction
  }

  /// Emits a raw heap allocation of a number of bytes, and gives back a
  /// non-NULL pointer.
  /// - parameter bytes: The number of bytes to allocate.
  /// - returns: An LLVM IR value that represents a heap-allocated value that
  ///            must be freed.
  func emitAlloc(bytes: Int, name: String = "") -> IRValue {
    let fn = emitIntrinsic(.alloc)
    return IGF.B.buildCall(
      fn, args: [IntType.int64.constant(bytes)], name: name)
  }

  /// Deallocates a heap value allocated via `silt_alloc`.
  /// - parameter value: The heap-allocated value.
  func emitDealloc(_ value: IRValue) {
    let fn = emitIntrinsic(.dealloc)
    _ = IGF.B.buildCall(fn, args: [value])
  }

  func emitIntrinsic(_ intrinsic: RuntimeIntrinsic) -> Function {
    if let fn = IGF.IGM.module.function(named: intrinsic.rawValue) {
      return fn
    }
    return IGF.B.addFunction(intrinsic.rawValue, type: intrinsic.type)
  }

  func emitCopyValue(_ value: IRValue, name: String = "") -> IRValue {
    let fn = emitIntrinsic(.copyValue)
    return IGF.B.buildCall(fn, args: [value], name: name)
  }

  func emitDestroyValue(_ value: IRValue) {
    let fn = emitIntrinsic(.destroyValue)
    _ = IGF.B.buildCall(fn, args: [value])
  }
}
