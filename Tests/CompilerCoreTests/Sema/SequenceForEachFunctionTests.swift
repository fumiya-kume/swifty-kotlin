@testable import CompilerCore
import Testing

/// KSP-1347: Validates that Sequence for-family functions resolve to bundled
/// Kotlin source declarations rather than synthetic runtime bridges.
@Suite
struct SequenceForEachFunctionTests {
    @Test func testSequenceForFamilyResolvesToBundledSource() throws {
        let ctx = makeContextFromSource("""
        fun printAll(values: Sequence<Int>) {
            values.forEach { value -> println(value) }
            values.forEachIndexed { index, value -> println(index + value) }
        }

        fun printFromLiteral() {
            sequenceOf(1, 2, 3).forEach { value -> println(value) }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence.forEach to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        for functionName in ["forEach", "forEachIndexed"] {
            let functionFQName = ["kotlin", "sequences", functionName]
                .map { ctx.interner.intern($0) }
            let sourceSymbol = try #require(
                sema.symbols.lookupAll(fqName: functionFQName).first(where: {
                    sema.symbols.isSourceBackedSymbol($0)
                }),
                "Expected bundled source declaration for Sequence.\(functionName)"
            )
            #expect(sema.symbols.symbol(sourceSymbol)?.declSite != nil)
            #expect(sema.symbols.externalLinkName(for: sourceSymbol) == nil)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == functionName
            })
            #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == sourceSymbol)
        }
    }
}
