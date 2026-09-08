#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ArrayConstructorResolutionTests {
    @Test
    func initializerConstructorResolvesToBundledSource() throws {
        let ctx = makeContextFromSource("""
        fun make(): Array<Int> = Array(3) { it * 2 }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Expected Array initializer to resolve: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(firstArrayCall(in: ast, ctx: ctx, argumentCount: 2))
        let chosen = try #require(
            sema.bindings.callBinding(for: call)?.chosenCallee,
            "Expected Array(size, init) to bind a source declaration"
        )
        let symbol = try #require(sema.symbols.symbol(chosen))
        let signature = try #require(sema.symbols.functionSignature(for: chosen))

        #expect(symbol.kind == .function)
        #expect(sema.symbols.isSourceBackedSymbol(chosen))
        #expect(sema.symbols.externalLinkName(for: chosen) == nil)
        #expect(signature.parameterTypes.count == 2)
        #expect(signature.typeParameterSymbols.count == 1)
    }

    @Test
    func sizeOnlyConstructorUsesCheckedCompilerAllocation() throws {
        let ctx = makeContextFromSource("""
        fun make(): Array<String?> = Array(2)
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Expected Array(size) to resolve: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(firstArrayCall(in: ast, ctx: ctx, argumentCount: 1))

        #expect(sema.bindings.callBinding(for: call)?.chosenCallee == nil)
        #expect(sema.bindings.stdlibSpecialCallKind(for: call) == .arrayConstructor)
    }

    private func firstArrayCall(
        in ast: ASTModule,
        ctx: CompilationContext,
        argumentCount: Int
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .call(callee, _, args, _) = ast.arena.expr(exprID),
                  args.count == argumentCount,
                  let range = ast.arena.exprRange(exprID),
                  !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_"),
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  ctx.interner.resolve(name) == "Array"
            else {
                continue
            }
            return exprID
        }
        return nil
    }
}
#endif
