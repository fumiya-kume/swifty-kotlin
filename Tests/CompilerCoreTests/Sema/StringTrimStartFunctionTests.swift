@testable import CompilerCore
import XCTest

final class StringTrimStartFunctionTests: XCTestCase {
    func testTrimStartNoArgResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripLeadingWhitespace(s: String): String {
            return s.trimStart()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testTrimStartWithPredicateResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripLeadingX(s: String): String {
            return s.trimStart { it == 'x' }
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
