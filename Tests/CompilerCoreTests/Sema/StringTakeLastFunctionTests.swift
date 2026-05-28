@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-080: Validates that `CharSequence.takeLast(n)` resolves through Sema for
/// `String` receivers. The synthetic stub links to `kk_string_takeLast`.
final class StringTakeLastFunctionTests: XCTestCase {
    func testTakeLastWithLiteralCount() throws {
        let ctx = makeContextFromSource("""
        fun lastThree(): String {
            return "hello".takeLast(3)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testTakeLastOnStringParameter() throws {
        let ctx = makeContextFromSource("""
        fun suffix(s: String, n: Int): String {
            return s.takeLast(n)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testTakeLastWithExpressionCount() throws {
        let ctx = makeContextFromSource("""
        fun lastHalf(s: String): String {
            return s.takeLast(s.length / 2)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testTakeLastChainedAfterTransform() throws {
        let ctx = makeContextFromSource("""
        fun greetingTail(name: String): String {
            return "Hello, ${name}!".takeLast(6)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
