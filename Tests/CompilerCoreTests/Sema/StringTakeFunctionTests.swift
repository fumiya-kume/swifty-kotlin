@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-078: Validates that `CharSequence.take(n)` resolves through
/// Sema for `String` receivers. The synthetic extension links to
/// `kk_string_take`, which trims the receiver to its first `n` scalars and
/// throws `IllegalArgumentException` when `n` is negative.
final class StringTakeFunctionTests: XCTestCase {
    func testTakeFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun firstThree(s: String): String {
            return s.take(3)
        }

        fun takeLiteral(): String {
            return "hello world".take(5)
        }

        fun takeFromExpression(value: Int): String {
            return value.toString().take(2)
        }

        fun takeAll(s: String): String {
            return s.take(s.length)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected take to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
