@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-031: Validates that `CharSequence?.isNullOrEmpty()` resolves
/// through Sema for both nullable and non-null String receivers, as documented
/// by the Sema fallback in `CallTypeChecker+MemberCallInferenceRegularNoCandidateFallbacks`.
/// Runtime link name involved: `kk_string_isNullOrEmpty`.
final class StringIsNullOrEmptyFunctionTests: XCTestCase {
    func testIsNullOrEmptyResolvesOnNullableAndNonNullStringReceivers() throws {
        let ctx = makeContextFromSource("""
        fun checkNullable(maybe: String?): Boolean {
            return maybe.isNullOrEmpty()
        }

        fun checkNonNull(s: String): Boolean {
            return s.isNullOrEmpty()
        }

        fun checkLiteral(): Boolean {
            return "hello".isNullOrEmpty()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected isNullOrEmpty to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
