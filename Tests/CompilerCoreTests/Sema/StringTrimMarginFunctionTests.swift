@testable import CompilerCore
import XCTest

final class StringTrimMarginFunctionTests: XCTestCase {
    func testTrimMarginNoArgResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripDefaultMargin(s: String): String {
            return s.trimMargin()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testTrimMarginWithCustomPrefixResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripGreaterThanMargin(s: String): String {
            return s.trimMargin(">")
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
