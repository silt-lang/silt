import XCTest

@testable import SiltSyntaxTests

#if !os(macOS)
XCTMain([
	SyntaxTestRunner.allTests,
])
#endif
