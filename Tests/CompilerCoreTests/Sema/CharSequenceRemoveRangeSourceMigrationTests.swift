@testable import CompilerCore
import Testing

/// KSP-1393: CharSequence.removeRange overloads are source-backed with the
/// Kotlin 2.3.10 CharSequence return contract and no runtime bridge.
@Suite
struct CharSequenceRemoveRangeSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringPrefixSuffix.kt"

    @Test
    func removeRangeDeclarationsAreSourceBacked() throws {
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
        let intRangeSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "ranges", "IntRange"].map(interner.intern))
        )
        let intRangeType = sema.types.make(.classType(ClassType(
            classSymbol: intRangeSymbol,
            args: [],
            nullability: .nonNull
        )))
        let intType = sema.types.intType
        let removeRangeSymbols = sema.symbols.lookupAll(
            fqName: ["kotlin", "text", "removeRange"].map(interner.intern)
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
        }

        #expect(removeRangeSymbols.count == 2, "Expected two source-backed CharSequence.removeRange overloads")
        let arities = Set(removeRangeSymbols.compactMap {
            sema.symbols.functionSignature(for: $0)?.parameterTypes
        })
        #expect(arities.contains([intType, intType]))
        #expect(arities.contains([intRangeType]))
        for symbolID in removeRangeSymbols {
            let symbol = try #require(sema.symbols.symbol(symbolID))
            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(signature.returnType == charSequenceType)
            #expect(!symbol.flags.contains(.inlineFunction))
            #expect(sema.symbols.isSourceBackedSymbol(symbolID))
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
        }
    }

    @Test
    func removeRangeCallsBindToTheSourceBackedOverloads() throws {
        let source = """
        class CustomSequence(private val value: String) : CharSequence {
            override val length: Int get() = value.length
            override fun get(index: Int): Char = value[index]
            override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
                value.substring(startIndex, endIndex)
        }

        fun removeRangeFamily(source: CharSequence): CharSequence {
            val direct: CharSequence = source.removeRange(1, 3)
            val closed: CharSequence = source.removeRange(1..2)
            val string: CharSequence = "A😀BC"
            val builder: CharSequence = StringBuilder("A😀BC")
            val custom: CharSequence = CustomSequence("A😀BC")
            string.removeRange(1, 3)
            builder.removeRange(1..2)
            custom.removeRange(1, 3)
            return if (direct.length == closed.length) string else custom
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let charSequenceSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "CharSequence"].map(ctx.interner.intern))
        )
        let charSequenceType = sema.types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        var calls: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, range) = ast.arena.expr(exprID),
                  range.start.file == userFileID,
                  ctx.interner.resolve(callee) == "removeRange"
            else {
                continue
            }
            calls.append(exprID)
            let binding = try #require(sema.bindings.callBinding(for: exprID))
            let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))
            let fileID = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            #expect(ctx.sourceManager.path(of: fileID) == sourcePath)
            #expect(!chosen.flags.contains(.synthetic))
            #expect(signature.returnType == charSequenceType)
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
        }

        #expect(calls.count == 5, "Expected five CharSequence.removeRange calls, got \(calls.count)")
    }
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
