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
            return source.first { return@first true }
        }

        fun explicitLambdaLabelReturn(source: CharSequence): Char {
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

    @Test func wrongEnclosingReturnTypeIsRejected() throws {
        let ctx = makeContextFromSource("""
        fun wrongOuterReturnType(source: CharSequence): Char {
            source.first { return "!" }
            return '?'
        }
        """)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func wrongLabeledPredicateReturnTypeIsRejected() throws {
        let ctx = makeContextFromSource("""
        fun wrongLabeledReturnType(source: CharSequence): Char {
            return source.first { return@first '!' }
        }
        """)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func localNamedFunctionResetsTheEnclosingReturnType() throws {
        let ctx = makeContextFromSource("""
        fun localNamedFunctionReturn(source: CharSequence): String {
            fun local(): Char {
                return source.first { return '!' }
            }
            local()
            return "?"
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
    }
}

private func assertHasDiagnostic(_ code: String, in ctx: CompilationContext) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    let descriptions = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
    #expect(found, "Expected diagnostic \(code), got: \(descriptions)")
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
