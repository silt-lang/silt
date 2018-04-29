import LLVM
import Seismography
import OuterCore

final class IRGenDataType {
  enum DataRepresentation {
    /// A plain-old-data data type. This type has no type parameters
    /// and only has constant constructors (think Bool).
    case simple

    /// A data type with complex constructors or type parameters.
    case complex
  }
  let type: DataType

  init(_ type: DataType) {
    self.type = type
  }
}
