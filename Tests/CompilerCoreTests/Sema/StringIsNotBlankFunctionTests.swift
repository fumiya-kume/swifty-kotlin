@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-029: Validates that `isNotBlank` resolves through Sema as a
/// synthetic extension on `String` (and `CharSequence` receivers).
/// Runtime link name: `kk_string_isNotBlank`.
final class StringIsNotBlankFunctionTests: XCTestCase {
    func testIsNotBlankFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun checkPlain(): Boolean {
            return "hello".isNotBlank()
        }

        fun checkSpaces(): Boolean {
            return "   ".isNotBlank()
        }

        fun checkOnReceiver(s: String): Boolean {
            return s.isNotBlank()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isNotBlank to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
