import XCTest

@testable import SyntaxTests
@testable import DiagnosticTests
@testable import LiteTests

#if !os(macOS)
XCTMain([
	SyntaxTestRunner.allTests,
	DiagnosticTests.allTests,
	LiteTests.allTests,
])
#endif
