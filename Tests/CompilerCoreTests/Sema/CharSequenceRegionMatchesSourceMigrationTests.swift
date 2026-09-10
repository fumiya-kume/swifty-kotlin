@testable import CompilerCore
import Testing

/// KSP-1392: CharSequence.regionMatches is source-backed and preserves the
/// Kotlin 2.3.10 defaulted ignoreCase parameter without a runtime bridge.
@Suite
struct CharSequenceRegionMatchesSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringComparison.kt"

    @Test
    func regionMatchesDeclarationIsSourceBacked() throws {
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
        let boolType = sema.types.booleanType
        let intType = sema.types.intType
        let regionMatchesSymbols = sema.symbols.lookupAll(
            fqName: ["kotlin", "text", "regionMatches"].map(interner.intern)
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

        #expect(regionMatchesSymbols.count == 1, "Expected one source-backed CharSequence.regionMatches")
        let symbolID = try #require(regionMatchesSymbols.first)
        let symbol = try #require(sema.symbols.symbol(symbolID))
        let signature = try #require(sema.symbols.functionSignature(for: symbolID))
        #expect(signature.parameterTypes == [
            intType,
            charSequenceType,
            intType,
            intType,
            boolType
        ])
        #expect(signature.returnType == boolType)
        #expect(!symbol.flags.contains(.inlineFunction))
        #expect(sema.symbols.isSourceBackedSymbol(symbolID))
        #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
    }

    @Test
    func regionMatchesCallsBindForStaticAndNamedReceivers() throws {
        let source = """
        class CustomSequence(private val value: String) : CharSequence {
            override val length: Int get() = value.length
            override fun get(index: Int): Char = value[index]
            override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
                value.substring(startIndex, endIndex)
        }

        fun regionMatchesFamily(source: CharSequence, other: CharSequence): Boolean {
            val direct = source.regionMatches(0, other, 0, 2)
            val named = source.regionMatches(
                thisOffset = 0,
                other = other,
                otherOffset = 0,
                length = 2,
                ignoreCase = true
            )
            val string: CharSequence = "Ab"
            val builder: CharSequence = StringBuilder("Ab")
            val custom: CharSequence = CustomSequence("Ab")
            string.regionMatches(0, "aB", 0, 2, true)
            builder.regionMatches(0, "aB", 0, 2, true)
            custom.regionMatches(0, "aB", 0, 2, true)
            return direct && named
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
                  ctx.interner.resolve(callee) == "regionMatches"
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
            #expect(signature.receiverType != nil)
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
        }

        #expect(calls.count == 5, "Expected five CharSequence.regionMatches calls, got \(calls.count)")
    }
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
