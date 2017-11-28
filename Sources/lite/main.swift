import Foundation
import LiteSupport

#if os(Linux)
import Glibc
#endif

exit(Int32(runLite()))
