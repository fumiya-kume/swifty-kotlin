#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-814: the initializer overload is bundled Kotlin source while the
/// size-only allocation remains the compiler-provided array constructor.
@Suite
struct ByteArrayConstructorResolutionTests {
    @Test
    func initializerResolvesToBundledSource() throws {
        let ctx = makeContextFromSource("""
        fun make(size: Int): ByteArray = ByteArray(size) { (it + 1).toByte() }
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected ByteArray initializer to resolve cleanly: \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(userCall(named: "ByteArray", arity: 2, ast: ast, ctx: ctx))
        let chosenCallee = try #require(
            sema.bindings.callBinding(for: callExpr)?.chosenCallee,
            "Expected ByteArray(size, init) to bind a source-backed declaration"
        )

        #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
        #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
    }

    @Test
    func sizeOnlyRemainsCompilerProvidedSpecialCall() throws {
        let ctx = makeContextFromSource("""
        fun make(size: Int): ByteArray = ByteArray(size)
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected ByteArray size-only allocation to resolve cleanly: \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(userCall(named: "ByteArray", arity: 1, ast: ast, ctx: ctx))

        #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == nil)
        #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .arrayConstructor)
    }

    private func userCall(
        named expectedName: String,
        arity: Int,
        ast: ASTModule,
        ctx: CompilationContext
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .call(callee, _, arguments, range) = expr,
                  case let .nameRef(name, _) = ast.arena.expr(callee)
            else {
                continue
            }
            guard ctx.sourceManager.origin(of: range.start.file) == .user,
                  ctx.interner.resolve(name) == expectedName,
                  arguments.count == arity
            else {
                continue
            }
            return exprID
        }
        return nil
    }
}
#endif
