@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-041: Validates that `CharSequence.padEnd(length, padChar)` resolves
/// through Sema for `String` receivers using both overloads.
/// - 1-arg overload (default padChar = ' ') links to `kk_string_padEnd_default`.
/// - 2-arg overload (explicit padChar) links to `kk_string_padEnd`.
final class StringPadEndFunctionTests: XCTestCase {
    func testPadEndFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun rightPadDefault(s: String): String {
            return s.padEnd(8)
        }

        fun rightPadWithChar(s: String): String {
            return s.padEnd(8, '*')
        }

        fun rightPadShorterThanSource(): String {
            return "hello".padEnd(3)
        }

        fun rightPadExpression(value: Int): String {
            return value.toString().padEnd(6, '0')
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected padEnd to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
