import LLVM
import Seismography
import OuterCore

final class IRGenFunction: PrimOpVisitor {
  unowned let IGM: IRGenModule
  let scope: Scope
  var function: Function?

  var B: IRBuilder {
    return IGM.B
  }

  init(irGenModule: IRGenModule, scope: Scope) {
    self.IGM = irGenModule
    self.scope = scope
  }

  func emitDeclaration() {
    let name = IGM.mangler.mangle(scope.entry)
    #warning("types need lowering (IRGenType?)")
    let type = FunctionType(argTypes: [], returnType: VoidType())
    self.function = B.addFunction(name, type: type)
  }

  func visitApplyOp(_ op: ApplyOp) {

  }

  func visitCopyValueOp(_ op: CopyValueOp) {

  }

  func visitDestroyValueOp(_ op: DestroyValueOp) {

  }

  func visitFunctionRefOp(_ op: FunctionRefOp) {

  }

  func visitSwitchConstrOp(_ op: SwitchConstrOp) {

  }

  func visitDataInitOp(_ op: DataInitOp) {

  }

  func visitUnreachableOp(_ op: UnreachableOp) {

  }
}
