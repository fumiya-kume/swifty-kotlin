#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-848: the FloatArray initializer overload is bundled Kotlin source,
/// while the size-only allocation remains the compiler-provided primitive.
@Suite
struct FloatArrayConstructorSourceMigrationTests {
    @Test
    func initializerResolvesToBundledSource() throws {
        let source = """
        fun initialize(size: Int): FloatArray = FloatArray(size) { index ->
            if (index == 0) 1.5f else 2.5f
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Expected FloatArray initializer to type-check cleanly: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(userCall(named: "FloatArray", argumentCount: 2, ast: ast, ctx: ctx))
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: call)?.chosenCallee,
                "Expected FloatArray(size, init) to bind its source-backed overload"
            )
            let symbol = try #require(sema.symbols.symbol(chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))

            #expect(symbol.kind == .function)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(signature.parameterTypes.count == 2)
            guard case let .classType(returnType) = sema.types.kind(of: signature.returnType),
                  let returnSymbol = sema.symbols.symbol(returnType.classSymbol)
            else {
                Issue.record("FloatArray initializer constructor should return a class type")
                return
            }
            #expect(ctx.interner.resolve(returnSymbol.name) == "FloatArray")
            let sourceFileID = try #require(sema.symbols.sourceFileID(for: chosenCallee))
            #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/FloatArray/Stdlib.kt")
        }
    }

    @Test
    func sizeOnlyAllocationRemainsCompilerProvided() throws {
        let source = """
        fun allocate(size: Int): FloatArray = FloatArray(size)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Expected FloatArray(size) to type-check cleanly: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let call = try #require(userCall(named: "FloatArray", argumentCount: 1, ast: ast, ctx: ctx))
            #expect(ctx.sema?.bindings.callBinding(for: call)?.chosenCallee == nil)
            #expect(ctx.sema?.bindings.stdlibSpecialCallKind(for: call) == .arrayConstructor)
        }
    }

    private func userCall(
        named expectedName: String,
        argumentCount: Int,
        ast: ASTModule,
        ctx: CompilationContext
    ) -> ExprID? {
        firstExprID(in: ast) { _, expr in
            guard case let .call(callee, _, args, range) = expr,
                  args.count == argumentCount,
                  ctx.sourceManager.origin(of: range.start.file)?.isBundledStdlib != true,
                  case let .nameRef(name, _) = ast.arena.expr(callee)
            else {
                return false
            }
            return ctx.interner.resolve(name) == expectedName
        }
    }
}
#endif
