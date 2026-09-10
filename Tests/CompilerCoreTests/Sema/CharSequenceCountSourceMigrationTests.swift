@testable import CompilerCore
import Testing

/// KSP-1370: Validates that CharSequence.count() is provided by bundled Kotlin
/// source with the Kotlin 2.3.10 inline contract and no runtime bridge.
@Suite
struct CharSequenceCountSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringHOF.kt"

    @Test
    func countDeclarationIsSourceBacked() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let charSequenceSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "CharSequence"].map(interner.intern))
        )
        let charSequenceType = sema.types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let countSymbols = sema.symbols.lookupAll(
            fqName: ["kotlin", "text", "count"].map(interner.intern)
        ).filter { id in
            guard let symbol = sema.symbols.symbol(id),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let fileID = sema.symbols.sourceFileID(for: id),
                  let signature = sema.symbols.functionSignature(for: id)
            else {
                return false
            }
            return ctx.sourceManager.path(of: fileID) == sourcePath
                && signature.receiverType == charSequenceType
                && signature.parameterTypes.isEmpty
        }

        #expect(countSymbols.count == 1, "Expected one source-backed CharSequence.count(), got \(countSymbols.count)")
        let countSymbol = try #require(countSymbols.first)
        #expect(sema.symbols.symbol(countSymbol)?.flags.contains(.inlineFunction) == true)
        #expect(sema.symbols.externalLinkName(for: countSymbol) == nil)
    }

    @Test
    func countCallsBindToTheSourceBackedExtension() throws {
        let source = """
        class CountingCharSequence(private val value: String) : CharSequence {
            override val length: Int get() = value.length
            override fun get(index: Int): Char = value[index]
            override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
                value.substring(startIndex, endIndex)
        }

        fun countFamily(source: CharSequence): Int {
            val string: String = "A😀"
            val builder: StringBuilder = StringBuilder("A😀")
            val custom: CountingCharSequence = CountingCharSequence("A😀")
            return source.count() + string.count() + builder.count() + custom.count() + "".count()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        var calls: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, range) = ast.arena.expr(exprID),
                  range.start.file == userFileID,
                  ctx.interner.resolve(callee) == "count"
            else {
                continue
            }
            calls.append(exprID)
            let binding = try #require(sema.bindings.callBinding(for: exprID))
            let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))
            let fileID = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            #expect(ctx.sourceManager.path(of: fileID) == sourcePath)
            #expect(!chosen.flags.contains(.synthetic))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
        }

        #expect(calls.count == 5, "Expected five CharSequence.count() calls, got \(calls.count)")
    }
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
