import LLVM
import Seismography
import OuterCore
import Mesosphere

final class IRGenModule {
  let B: IRBuilder
  let girModule: GIRModule
  let module: Module
  let mangler = GIRMangler()
  private(set) var scopeMap = [Scope: IRGenFunction]()

  init(module: GIRModule) {
    self.girModule = module
    self.module = Module(name: mangler.mangleIdentifier(girModule.name))
    self.B = IRBuilder(module: self.module)
  }

  func emit() {
    for scope in girModule.topLevelScopes {
      let igf = IRGenFunction(irGenModule: self, scope: scope)
      scopeMap[scope] = igf
      igf.emitDeclaration()
    }
  }
}
