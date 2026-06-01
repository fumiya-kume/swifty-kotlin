@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-074: Validates that `String.substringAfter(delimiter, missingDelimiterValue)`
/// resolves through Sema for both `String` and `Char` delimiter overloads with optional
/// `missingDelimiterValue` parameter.
/// - 1-arg String delimiter: `kk_string_substringAfter` with default missingDelimiterValue = receiver.
/// - 2-arg String delimiter + missingDelimiterValue: `kk_string_substringAfter`.
/// - 1-arg Char delimiter: `kk_string_substringAfter_char`.
/// - 2-arg Char delimiter + missingDelimiterValue: `kk_string_substringAfter_char`.
final class StringSubstringAfterFunctionTests: XCTestCase {
    func testSubstringAfterFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun afterStringDelimiter(s: String): String {
            return s.substringAfter(".")
        }

        fun afterStringDelimiterWithDefault(s: String, missing: String): String {
            return s.substringAfter(".", missing)
        }

        fun afterCharDelimiter(s: String): String {
            return s.substringAfter('.')
        }

        fun afterCharDelimiterWithDefault(s: String, missing: String): String {
            return s.substringAfter('.', missing)
        }

        fun afterLiteralReceiver(): String {
            return "hello.world.kt".substringAfter(".")
        }

        fun afterLiteralReceiverChar(): String {
            return "hello.world.kt".substringAfter('.')
        }

        fun afterMissingValueLiteral(): String {
            return "no-delimiter-here".substringAfter("@", "fallback")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected substringAfter to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
