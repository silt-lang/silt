import LLVM

enum RuntimeIntrinsic: String {
  case copyValue = "silt_copyValue"
  case destroyValue = "silt_destroyValue"

  var type: FunctionType {
    switch self {
    case .copyValue:
      return FunctionType(argTypes: [PointerType.toVoid],
                          returnType: PointerType.toVoid)
    case .destroyValue:
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
