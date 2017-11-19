import Lithosphere
import Drill
import XCTest

/// A diagnostic consumer that emits an XCTFail with the serialized
/// diagnostic whenever a diagnostic is emitted.
public class XCTestFailureConsumer: DiagnosticConsumer {
    /// A reference type that exists to keep alive a String.
    private class StreamBuffer: TextOutputStream {
        var value = ""
        func write(_ string: String) {
            value += string
        }
        func clear() {
            value = ""
        }
    }

    /// A buffer for each diagnostic.
    private var scratch = StreamBuffer()

    /// A printing diagnostic consumer that will serialize diagnostics
    /// to a string.
    private let printer: PrintingDiagnosticConsumer<StreamBuffer>

    public init() {
        printer = .init(stream: &scratch)
    }

    /// XCTFails with the serialized version of the diagnostic provided.
    public func handle(_ diagnostic: Diagnostic) {
        scratch.clear()
        printer.handle(diagnostic)
        XCTFail(scratch.value)
    }

    public func finalize() {
        // Do nothing
    }
}
