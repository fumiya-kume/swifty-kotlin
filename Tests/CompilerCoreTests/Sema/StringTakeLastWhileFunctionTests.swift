@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-081: Validates that `CharSequence.takeLastWhile(predicate)` resolves
/// through Sema for `String` receivers. The synthetic stub links to `kk_string_takeLastWhile`.
final class StringTakeLastWhileFunctionTests: XCTestCase {
    func testTakeLastWhileWithSimpleLambda() throws {
        let ctx = makeContextFromSource("""
        fun trailingLetters(s: String): String {
            return s.takeLastWhile { it.isLetter() }
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testTakeLastWhileOnStringLiteral() throws {
        let ctx = makeContextFromSource("""
        fun trailDigits(): String {
            return "abc123".takeLastWhile { it.isDigit() }
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testTakeLastWhileReturnTypeIsString() throws {
        let ctx = makeContextFromSource("""
        fun trailingLower(s: String): String {
            return s.takeLastWhile { it.isLowerCase() }
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testTakeLastWhileChainedAfterTransform() throws {
        let ctx = makeContextFromSource("""
        fun trimmedSuffix(s: String): String {
            return s.trim().takeLastWhile { it != ' ' }
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
