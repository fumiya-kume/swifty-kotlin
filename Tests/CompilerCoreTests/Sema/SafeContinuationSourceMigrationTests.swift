#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SafeContinuationSourceMigrationTests {
    @Test
    func safeContinuationConstructorIsBundledSourceBacked() throws {
        let source = """
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        import kotlin.coroutines.Continuation

        fun construct(delegate: Continuation<Int>): kotlin.coroutines.SafeContinuation<Int> =
            kotlin.coroutines.SafeContinuation<Int>(delegate)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected SafeContinuation source to type-check, got: \(errors.map { error in "\(error.code): \(error.message)" })"
            )

            let sema = try #require(ctx.sema)
            let safeContinuationFQName = ["kotlin", "coroutines", "SafeContinuation"].map(ctx.interner.intern)
            let safeContinuation = try #require(sema.symbols.lookup(fqName: safeContinuationFQName))
            let safeContinuationInfo = try #require(sema.symbols.symbol(safeContinuation))
            #expect(safeContinuationInfo.kind == .class)
            #expect(!safeContinuationInfo.flags.contains(.synthetic))
            #expect(
                sourcePath(for: safeContinuation, sema: sema, ctx: ctx)?.contains(
                    "__bundled_kotlin/coroutines/SafeContinuation/Stdlib.kt"
                ) == true
            )

            let constructorFQName = safeContinuationFQName + [ctx.interner.intern("<init>")]
            let constructor = try #require(
                sema.symbols.lookupAll(fqName: constructorFQName).first { symbolID in
                    sema.symbols.symbol(symbolID)?.kind == .constructor
                }
            )
            #expect(sema.symbols.symbol(constructor)?.visibility == .internal)
            #expect(sema.symbols.isSourceBackedSymbol(constructor))
            #expect(sema.symbols.externalLinkName(for: constructor) == nil)
            #expect(try #require(sema.symbols.functionSignature(for: constructor)).parameterTypes.count == 1)

            let ast = try #require(ctx.ast)
            let constructorCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                return sema.bindings.callBinding(for: exprID)?.chosenCallee == constructor
                    ? exprID
                    : nil
            }
            let constructorCall = try #require(constructorCalls.first)
            #expect(sema.bindings.callBinding(for: constructorCall)?.chosenCallee == constructor)
        }
    }

    private func sourcePath(
        for symbol: SymbolID,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> String? {
        let fileID = sema.symbols.sourceFileID(for: symbol)
            ?? sema.symbols.symbol(symbol)?.declSite?.start.file
            ?? sema.symbols.parentSymbol(for: symbol).flatMap { sema.symbols.sourceFileID(for: $0) }
        guard let fileID else { return nil }
        return ctx.sourceManager.path(of: fileID)
    }
}
#endif
