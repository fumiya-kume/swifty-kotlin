@testable import CompilerCore
import Testing

/// KSP-1385: Validates the CharSequence map destination family is provided by
/// bundled Kotlin source and binds without synthetic runtime bridges.
@Suite
struct CharSequenceMapSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringHOF.kt"

    @Test
    func mapFamilyDeclarationsAreSourceBacked() throws {
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
        let packageFQName = ["kotlin", "text"].map(interner.intern)
        let expectedArities: [String: Int] = [
            "mapIndexedNotNull": 1,
            "mapIndexedNotNullTo": 2,
            "mapIndexedTo": 2,
            "mapNotNullTo": 2,
            "mapTo": 2,
        ]

        for (name, arity) in expectedArities {
            let symbols = sema.symbols.lookupAll(fqName: packageFQName + [interner.intern(name)]).filter { id in
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
                    && signature.parameterTypes.count == arity
            }

            #expect(symbols.count == 1, "Expected one CharSequence.(name) declaration, got \(symbols.count)")
            for symbolID in symbols {
                let symbol = try #require(sema.symbols.symbol(symbolID))
                #expect(symbol.flags.contains(.inlineFunction))
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
            }
        }
    }

    @Test
    func mapFamilyCallsBindToBundledSource() throws {
        let source = """
        fun mapFamily(source: CharSequence, destination: MutableList<Any?>): List<Any?> {
            val indexedNotNull: List<Int> = source.mapIndexedNotNull { index, _ ->
                if (index == 0) index else null
            }
            source.mapIndexedNotNullTo(destination) { index, _ -> if (index == 0) index else null }
            source.mapIndexedTo(destination) { index, value -> if (index == 0) value else index }
            source.mapNotNullTo(destination) { if (it == 'a') it.code else null }
            source.mapTo(destination) { it.code }
            return indexedNotNull
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
        let names = Set(["mapIndexedNotNull", "mapIndexedNotNullTo", "mapIndexedTo", "mapNotNullTo", "mapTo"])
        var calls: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, range) = ast.arena.expr(exprID),
                  range.start.file == userFileID,
                  names.contains(ctx.interner.resolve(callee))
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

        #expect(calls.count == names.count, "Expected five CharSequence map calls, got \(calls.count)")
    }

    @Test
    func mapFamilyAcceptsNonLocalReturnInInlineTransform() throws {
        let source = """
        fun mapToNonLocal(source: CharSequence): String {
            val destination: MutableList<String> = mutableListOf()
            source.mapTo<String, MutableList<String>>(destination) { return "!" }
            return "?"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))
    }
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
