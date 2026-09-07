@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-042: Validates that `Sequence<T>.fold(initial: R, operation: (R, T) -> R): R`
/// resolves via the source-backed Sequence aggregate HOF implementation.
/// KSP-1346: Sequence.fold is implemented in the canonical kotlin.sequences
/// source file, so there is no synthetic `kk_sequence_fold` runtime stub.
@Suite
struct SequenceFoldFunctionTests {
    @Test func testSequenceFoldResolvesToCanonicalSource() throws {
        let ctx = makeContextFromSource("""
        fun sumValues(values: Sequence<Int>): Int {
            return values.fold(0) { acc, value -> acc + value }
        }

        fun concatValues(values: Sequence<Int>): String {
            return values.fold("") { acc, value -> acc + value.toString() }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence.fold to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExprID = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "fold"
        }, "Expected fold member call")

        let binding = try #require(sema.bindings.callBinding(for: callExprID))
        let chosenCallee = try #require(binding.chosenCallee)
        let fqName = try #require(sema.symbols.symbol(chosenCallee)?.fqName)
            .map { ctx.interner.resolve($0) }
        #expect(fqName == ["kotlin", "sequences", "fold"])
        #expect(
            sema.symbols.symbol(chosenCallee)?.declSite != nil,
            "Expected Sequence.fold call to resolve to the source-backed extension"
        )
        #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        #expect(sema.bindings.exprType(for: callExprID) == sema.types.intType)
    }
}
