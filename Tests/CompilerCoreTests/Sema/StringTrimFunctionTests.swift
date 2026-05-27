@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-110: Validates that `kotlin.text.CharSequence.trim` resolves
/// through Sema for both the no-arg overload and the predicate-based overload.
/// Runtime link names involved: `kk_string_trim`, `kk_string_trim_predicate`.
final class StringTrimFunctionTests: XCTestCase {
    func testTrimFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun trimDefault(s: String): String {
            return s.trim()
        }

        fun trimWithPredicate(s: String): String {
            return s.trim { it == 'x' }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected trim to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
