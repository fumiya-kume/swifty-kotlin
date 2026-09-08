#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1402: the CharSequence IntRange overload is backed by bundled Kotlin
/// source and routes through the nominal CharSequence subSequence member.
@Suite
struct CharSequenceSubSequenceSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringSubstringSlice.kt"

    @Test
    func rangeOverloadIsSourceBackedWithExactSignature() throws {
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

        let fqName = ["kotlin", "text", "subSequence"].map(interner.intern)
        let matches = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let fileID = sema.symbols.sourceFileID(for: symbolID),
                  let signature = sema.symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return ctx.sourceManager.path(of: fileID) == sourcePath
                && signature.receiverType == charSequenceType
                && signature.parameterTypes == [intRangeType]
                && signature.returnType == charSequenceType
        }

        #expect(matches.count == 1, "Expected one source-backed CharSequence.subSequence(IntRange)")
        let symbolID = try #require(matches.first)
        let symbol = try #require(sema.symbols.symbol(symbolID))
        #expect(!symbol.flags.contains(.inlineFunction))
        #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
        #expect(sema.symbols.isSourceBackedSymbol(symbolID))
    }

    @Test
    func rangeCallsBindToSourceDefinition() throws {
        let source = """
        fun probe(source: CharSequence): CharSequence {
            val head: CharSequence = source.subSequence(1..3)
            val empty: CharSequence = source.subSequence(2 until 2)
            return head
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
        var chosen: [SymbolID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, range) = ast.arena.expr(exprID),
                  range.start.file == userFileID,
                  ctx.interner.resolve(callee) == "subSequence",
                  let binding = sema.bindings.callBinding(for: exprID)
            else {
                continue
            }
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            guard signature.parameterTypes.count == 1 else { continue }
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
            #expect(ctx.sourceManager.path(of: sema.symbols.sourceFileID(for: binding.chosenCallee) ?? .invalid) == sourcePath)
            chosen.append(binding.chosenCallee)
        }

        #expect(chosen.count == 2, "Expected two CharSequence.subSequence(IntRange) calls")
        #expect(Set(chosen).count == 1, "Range calls should bind to one source-backed overload")
    }

    @Test
    func concreteCharSequenceSubtypesUseRangeSourceFallback() throws {
        let source = """
        class PlainSequence(private val value: String): CharSequence {
            override val length: Int get() = value.length
            override fun get(index: Int): Char = value[index]
            override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
                value.substring(startIndex, endIndex)
        }

        fun probe(plain: PlainSequence, builder: StringBuilder): CharSequence {
            val plainRange = plain.subSequence(0..1)
            val builderRange = builder.subSequence(0..1)
            return plainRange
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
        var chosen: [SymbolID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, args, range) = ast.arena.expr(exprID),
                  range.start.file == userFileID,
                  ctx.interner.resolve(callee) == "subSequence",
                  args.count == 1,
                  let binding = sema.bindings.callBinding(for: exprID)
            else {
                continue
            }
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            #expect(signature.parameterTypes.count == 1)
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            #expect(!sema.symbols.symbol(binding.chosenCallee)!.flags.contains(.synthetic))
            #expect(ctx.sourceManager.path(of: sema.symbols.sourceFileID(for: binding.chosenCallee) ?? .invalid) == sourcePath)
            chosen.append(binding.chosenCallee)
        }

        #expect(chosen.count == 2, "Concrete CharSequence subtype calls should use the source-backed IntRange overload")
        #expect(Set(chosen).count == 1)
    }

    @Test
    func visibleUserRangeExtensionWinsOverSyntheticFallback() throws {
        let source = """
        fun CharSequence.subSequence(range: IntRange): CharSequence = "user"

        fun probe(source: CharSequence, text: String): CharSequence {
            val literalRange = source.subSequence(0..1)
            val namedRange = source.subSequence(range = 0..1)
            val variableRange = source.subSequence(0..1)
            val stringRange = text.subSequence(0..1)
            return literalRange
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
        var chosen: [SymbolID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, range) = ast.arena.expr(exprID),
                  range.start.file == userFileID,
                  ctx.interner.resolve(callee) == "subSequence",
                  let binding = sema.bindings.callBinding(for: exprID)
            else {
                continue
            }
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            guard signature.parameterTypes.count == 1 else { continue }
            #expect(sema.symbols.sourceFileID(for: binding.chosenCallee) == userFileID)
            #expect(!sema.symbols.symbol(binding.chosenCallee)!.flags.contains(.synthetic))
            chosen.append(binding.chosenCallee)
        }

        #expect(chosen.count == 4, "All visible IntRange extension calls should bind to the user declaration")
        #expect(Set(chosen).count == 1)
    }

    @Test
    func invalidRangeCallsDoNotUseSyntheticFallback() throws {
        let source = """
        fun probe(source: CharSequence) {
            source.subSequence(unexpected = 0..1)
            source.subSequence("not a range")
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(ctx.diagnostics.hasError)
    }
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
#endif
