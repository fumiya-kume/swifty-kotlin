@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-052: Validates that `kotlin.text.CharSequence.removeSuffix(suffix)`
/// resolves through Sema for `String` / `CharSequence` receivers, dispatching to the
/// runtime link name `kk_string_removeSuffix`.
final class StringRemoveSuffixFunctionTests: XCTestCase {
    func testRemoveSuffixFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripSuffix(s: String): String {
            return s.removeSuffix("World")
        }

        fun removeSuffixLiteral(): String {
            return "HelloWorld".removeSuffix("World")
        }

        fun removeSuffixNoMatch(): String {
            return "HelloWorld".removeSuffix("Earth")
        }

        fun removeSuffixEmpty(): String {
            return "".removeSuffix("suffix")
        }

        fun removeSuffixExact(): String {
            return "suffix".removeSuffix("suffix")
        }

        fun removeSuffixOnExpression(value: Int): String {
            return value.toString().removeSuffix("0")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected removeSuffix to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
