import XCTest

@testable import SyntaxTests
@testable import DiagnosticTests

#if !os(macOS)
XCTMain([
	SyntaxTestRunner.allTests,
	DiagnosticTests.allTests,
])
#endif
