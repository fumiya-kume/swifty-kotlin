#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CharSequenceChunkedSourceMigrationTests {
    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }

    @Test
    func chunkedOverloadsAreBundledSourceDefinitions() throws {
        let ctx = try sharedCtx()
        let sema = try #require(ctx.sema)
        let chunkedFQName = ["kotlin", "text", "chunked"].map(ctx.interner.intern)
        let sourceSymbols = sema.symbols.lookupAll(fqName: chunkedFQName).filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let fileID = sema.symbols.sourceFileID(for: symbolID)
            else {
                return false
            }
            return ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/text/StringWindowChunkTransform.kt"
        }
        let registeredArities = Set(sourceSymbols.compactMap { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count
        })

        #expect(registeredArities.contains(1))
        #expect(registeredArities.contains(2))
        #expect(sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        #expect(sourceSymbols.allSatisfy { sema.symbols.functionSignature(for: $0)?.receiverType != nil })
    }

    @Test
    func chunkedTransformCallsBindToPublicOverload() throws {
        let source = """
        fun chunkLengths(value: CharSequence): List<Int> {
            return value.chunked(2) { it.length }
        }

        fun stringChunks(value: String): List<String> {
            return value.chunked(2) { it.toString() }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Expected CharSequence.chunked transform to type-check")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let chunkedFQName = ["kotlin", "text", "chunked"].map(ctx.interner.intern)
            let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "chunked"
                else {
                    return nil
                }
                return exprID
            }
            #expect(calls.count == 2)
            for call in calls {
                let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
                #expect(sema.symbols.symbol(chosen)?.fqName == chunkedFQName)
                #expect(sema.symbols.externalLinkName(for: chosen) == nil)
                let fileID = try #require(sema.symbols.sourceFileID(for: chosen))
                #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/text/StringWindowChunkTransform.kt")
            }
        }
    }
}
#endif
