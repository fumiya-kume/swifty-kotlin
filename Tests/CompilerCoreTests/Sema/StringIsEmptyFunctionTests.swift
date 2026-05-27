@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-028: Validates that `String.isEmpty()` resolves through Sema
/// for `String` / `CharSequence` receivers, dispatching to the runtime link
/// name `kk_string_isEmpty`.
final class StringIsEmptyFunctionTests: XCTestCase {
    func testIsEmptyFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun isStringEmpty(s: String): Boolean {
            return s.isEmpty()
        }

        fun isEmptyLiteral(): Boolean {
            return "".isEmpty()
        }

        fun isNonEmptyLiteral(): Boolean {
            return "hello".isEmpty()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isEmpty to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
