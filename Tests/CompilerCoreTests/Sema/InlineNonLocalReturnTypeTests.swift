@testable import CompilerCore
import Testing

/// Covers the type of an unlabeled return that exits a lambda passed to an
/// inline higher-order function. The lambda's Boolean predicate type must not
/// be used as the expected type for the returned value.
@Suite
struct InlineNonLocalReturnTypeTests {
    @Test func nonLocalReturnsUseTheEnclosingFunctionType() throws {
        let ctx = makeContextFromSource("""
        fun firstNonLocal(source: CharSequence): Char {
            return source.first { return '!' }
        }

        fun firstConditionalNonLocal(source: CharSequence): Char {
            return source.first { ch ->
                if (ch == 'x') return '!'
                false
            }
        }

        fun trimNonLocal(source: String): String {
            source.trim { return "!" }
            return "?"
        }

        fun trimStartNonLocal(source: String): String {
            source.trimStart { return "!" }
            return "?"
        }

        fun labeledPredicateReturn(source: CharSequence): Char {
            return source.first predicate@ { return@predicate true }
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected non-local return values to use the enclosing function type, got: "
                + errors.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            )
        )
    }
}
