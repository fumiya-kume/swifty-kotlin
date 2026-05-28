@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-015: Validates that `CharSequence.endsWith(suffix)` resolves
/// through Sema for `String` receivers, dispatching to the runtime link name
/// `kk_string_endsWith`.
final class StringEndsWithFunctionTests: XCTestCase {
    func testEndsWithFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stringEndsWithSuffix(s: String): Boolean {
            return s.endsWith("lin")
        }

        fun literalEndsWith(): Boolean {
            return "Kotlin".endsWith("lin")
        }

        fun literalEndsWithMismatch(): Boolean {
            return "Kotlin".endsWith("XYZ")
        }

        fun emptySuffixIsAlwaysTrue(s: String): Boolean {
            return s.endsWith("")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected endsWith to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
