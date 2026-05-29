@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-111: Validates that `String.trimEnd` resolves through Sema for
/// both the zero-argument whitespace overload and the predicate overload.
/// The zero-arg form binds to runtime link `kk_string_trimEnd`, while the
/// predicate form binds to `kk_string_trimEnd_predicate`.
final class StringTrimEndFunctionTests: XCTestCase {
    func testTrimEndFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun trimWhitespace(s: String): String {
            return s.trimEnd()
        }

        fun trimWithPredicate(s: String): String {
            return s.trimEnd { it == 'x' }
        }

        fun trimWithNamedPredicate(s: String): String {
            return s.trimEnd(predicate = { ch -> ch == ' ' || ch == '\\t' })
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected String.trimEnd overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
