import LLVM
import Seismography
import OuterCore
import PrettyStackTrace

final class IRGenModule {
  let B: IRBuilder
  let girModule: GIRModule
  let module: Module
  let mangler = GIRMangler()
  private(set) var scopeMap = [Scope: IRGenFunction]()
  private(set) var dataTypeMap = [DataType: IRGenDataType]()

  init(module: GIRModule) {
    self.girModule = module
    self.module = Module(name: mangler.mangle(girModule))
    self.B = IRBuilder(module: self.module)
  }

  func emit() {
    trace("emitting LLVM IR for module '\(girModule.name)'") {
      for scope in girModule.topLevelScopes {
        let igf = IRGenFunction(irGenModule: self, scope: scope)
        scopeMap[scope] = igf
        igf.emitDeclaration()
      }
      for (_, igf) in scopeMap {
        igf.emitBody()
      }
    }
  }

  func emitMain() {
    let fn = B.addFunction("main", type: FunctionType(
      argTypes: [],
      returnType: IntType.int32
    ))
    let entry = fn.appendBasicBlock(named: "entry")
    B.positionAtEnd(of: entry)
    let andFn = module.function(named: "_SC9bool._&&_")!
    let call = B.buildCall(andFn, args: [true, false])
    let retVal = B.buildZExt(call, type: IntType.int32)
    B.buildRet(retVal)
  }
}
