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
