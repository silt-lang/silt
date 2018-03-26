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
}
