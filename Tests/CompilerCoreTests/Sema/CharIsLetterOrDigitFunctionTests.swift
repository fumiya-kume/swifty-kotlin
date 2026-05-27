@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-012: Validates that `kotlin.text.isLetterOrDigit` resolves
/// through Sema as a Char extension (Kotlin spec defines it as `fun
/// Char.isLetterOrDigit(): Boolean`). The runtime link name involved is
/// `kk_char_isLetterOrDigit`.
final class CharIsLetterOrDigitFunctionTests: XCTestCase {
    func testIsLetterOrDigitResolvesOnCharLiteralReceiver() throws {
        let ctx = makeContextFromSource("""
        fun letterOrDigitOfLiteral(): Boolean {
            return 'A'.isLetterOrDigit()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isLetterOrDigit to type-check on a Char literal, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIsLetterOrDigitResolvesOnCharParameterReceiver() throws {
        let ctx = makeContextFromSource("""
        fun isAlnum(ch: Char): Boolean {
            return ch.isLetterOrDigit()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isLetterOrDigit to type-check on a Char parameter, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
