@testable import CompilerCore
import Testing

/// KSP-1399: CharSequence single-family overloads are bundled-source functions
/// with direct indexed dispatch and no StringQuery runtime links.
@Suite
struct CharSequenceSingleSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringQuery.kt"

    @Test
    func singleFamilyDeclarationsAreSourceBacked() throws {
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
        let expected: [(name: String, arity: Int, inline: Bool, nullable: Bool)] = [
            ("single", 0, false, false),
            ("single", 1, true, false),
            ("singleOrNull", 0, false, true),
            ("singleOrNull", 1, true, true),
        ]

        for item in expected {
            let candidates = sema.symbols.lookupAll(
                fqName: ["kotlin", "text", item.name].map(interner.intern)
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
                    && signature.parameterTypes.count == item.arity
            }

            #expect(candidates.count == 1, "Expected one source-backed \(item.name)/\(item.arity)")
            let symbolID = try #require(candidates.first)
            let symbol = try #require(sema.symbols.symbol(symbolID))
            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(symbol.flags.contains(.inlineFunction) == item.inline)
            #expect(sema.symbols.isSourceBackedSymbol(symbolID))
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
            let expectedReturn = item.nullable
                ? sema.types.makeNullable(sema.types.charType)
                : sema.types.charType
            #expect(signature.returnType == expectedReturn)
        }
    }

    @Test
    func staticCharSequenceCallsBindToTheSingleFamily() throws {
        let source = """
        fun singleFamily(source: CharSequence, wanted: Char): Char? {
            val direct = source.single()
            val predicate = source.single { it == wanted }
            val named = source.single(predicate = { it == wanted })
            val nullDirect = source.singleOrNull()
            val nullPredicate = source.singleOrNull { it == wanted }
            val nullNamed = source.singleOrNull(predicate = { it == wanted })
            val string: CharSequence = "S"
            val builder: CharSequence = StringBuilder("B")
            string.single()
            builder.singleOrNull()
            return nullNamed ?: nullPredicate ?: nullDirect ?: direct ?: predicate ?: named
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let names: Set<String> = ["single", "singleOrNull"]
        var calls = 0
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, range) = ast.arena.expr(exprID),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  names.contains(ctx.interner.resolve(callee))
            else {
                continue
            }
            calls += 1
            let binding = try #require(sema.bindings.callBinding(for: exprID))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            let fileID = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            #expect(ctx.sourceManager.path(of: fileID) == sourcePath)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
            if signature.parameterTypes.count == 1 {
                #expect(symbol.flags.contains(.inlineFunction))
            }
        }

        #expect(calls == 8, "Expected eight CharSequence single-family calls, got \(calls)")
    }
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
