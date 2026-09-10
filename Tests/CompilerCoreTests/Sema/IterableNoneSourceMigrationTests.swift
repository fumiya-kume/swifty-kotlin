#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IterableNoneSourceMigrationTests {
    @Test
    func iterableNoneWithoutPredicateIsSourceBacked() throws {
        try assertSourceBackedNone(
            source: """
            fun probe(values: Iterable<Int>): Boolean = values.none()
            """,
            parameterCount: 0,
            isInline: false
        )
    }

    @Test
    func iterableNoneWithPredicateIsSourceBackedInline() throws {
        try assertSourceBackedNone(
            source: """
            fun probe(values: Iterable<Int>): Boolean = values.none { it > 1 }
            """,
            parameterCount: 1,
            isInline: true
        )
    }

    private func assertSourceBackedNone(
        source: String,
        parameterCount: Int,
        isInline: Bool
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected Iterable.none to type-check cleanly"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "none"
            }, "Expected an Iterable.none member call")
            let binding = try #require(sema.bindings.callBinding(for: call))
            let chosen = try #require(binding.chosenCallee)
            let symbol = try #require(sema.symbols.symbol(chosen))
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            let receiver = try #require(signature.receiverType)
            let iterableSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Iterable"),
            ]))

            #expect(sema.symbols.isSourceBackedSymbol(chosen))
            #expect(sema.symbols.externalLinkName(for: chosen) == nil)
            #expect(signature.parameterTypes.count == parameterCount)
            #expect(symbol.flags.contains(.inlineFunction) == isInline)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiver) else {
                Issue.record("Iterable.none receiver was not a class type")
                return
            }
            #expect(receiverClass.classSymbol == iterableSymbol)
        }
    }
}
#endif
