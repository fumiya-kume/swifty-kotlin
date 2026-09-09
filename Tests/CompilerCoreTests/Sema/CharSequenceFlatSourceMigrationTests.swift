@testable import CompilerCore
import Testing

/// KSP-1375: Validates the CharSequence flat family is provided by bundled
/// Kotlin source and binds without a synthetic runtime bridge.
@Suite
struct CharSequenceFlatSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringHOF.kt"

    @Test
    func flatFamilyDeclarationsAreSourceBacked() throws {
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
            "flatMap": 1,
            "flatMapIndexed": 1,
            "flatMapIndexedTo": 2,
            "flatMapTo": 2,
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
    func flatFamilyCallsBindToBundledSource() throws {
        let source = """
        fun flatFamily(source: CharSequence, destination: MutableList<Any?>): List<Any?> {
            val flat: List<Any?> = source.flatMap { listOf<Any?>(it, null) }
            val indexed: List<Any?> = source.flatMapIndexed { index, value -> listOf<Any?>(index, value) }
            source.flatMapTo(destination) { listOf<Any?>(it) }
            source.flatMapIndexedTo(destination) { index, value -> listOf<Any?>(index, value) }
            return flat + indexed
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
        let names = Set(["flatMap", "flatMapIndexed", "flatMapIndexedTo", "flatMapTo"])
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

        #expect(calls.count == names.count, "Expected four CharSequence flat calls, got \(calls.count)")
    }

    @Test
    func flatFamilyAcceptsNonLocalReturnsInInlineTransforms() throws {
        let source = """
        fun flatNonLocal(source: CharSequence): String {
            source.flatMap<String> { return "!" }
            return "?"
        }
        fun flatIndexedNonLocal(source: CharSequence): String {
            source.flatMapIndexed<String> { _, _ -> return "!" }
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
