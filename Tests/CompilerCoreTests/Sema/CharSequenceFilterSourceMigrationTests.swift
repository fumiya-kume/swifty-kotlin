@testable import CompilerCore
import Testing

/// KSP-1373: Validates that the CharSequence filter family is provided by
/// bundled Kotlin source with the Kotlin 2.3.10 surface and no runtime bridge.
@Suite
struct CharSequenceFilterSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringHOF.kt"

    @Test
    func filterFamilyDeclarationsAreSourceBacked() throws {
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
            "filter": 1,
            "filterIndexed": 1,
            "filterIndexedTo": 2,
            "filterNot": 1,
            "filterNotTo": 2,
            "filterTo": 2,
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

            #expect(symbols.count == 1, "Expected one CharSequence.(name) declaration, got (symbols.count)")
            for symbolID in symbols {
                let symbol = try #require(sema.symbols.symbol(symbolID))
                #expect(symbol.flags.contains(.inlineFunction))
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
            }
        }

        let directReturnTypes = ["filter", "filterIndexed", "filterNot"]
        for name in directReturnTypes {
            let symbolID = try #require(
                sema.symbols.lookupAll(fqName: packageFQName + [interner.intern(name)]).first { id in
                    sema.symbols.functionSignature(for: id)?.receiverType == charSequenceType
                        && ctx.sourceManager.path(of: sema.symbols.sourceFileID(for: id) ?? .invalid) == sourcePath
                }
            )
            #expect(sema.symbols.functionSignature(for: symbolID)?.returnType == charSequenceType)
        }
    }

    @Test
    func filterFamilyCallsBindToBundledSource() throws {
        let source = """
        fun filterFamily(source: CharSequence): CharSequence {
            val filtered: CharSequence = source.filter { it == 'a' }
            val indexed: CharSequence = source.filterIndexed { index, _ -> index % 2 == 0 }
            val notFiltered: CharSequence = source.filterNot { it == 'x' }
            val destination = StringBuilder()
            source.filterTo(destination) { it != '-' }
            source.filterNotTo(destination) { it == '-' }
            source.filterIndexedTo(destination) { index, _ -> index % 2 == 0 }
            return filtered
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
        let names = Set(["filter", "filterIndexed", "filterIndexedTo", "filterNot", "filterNotTo", "filterTo"])
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

        #expect(calls.count == names.count, "Expected six CharSequence filter calls, got (calls.count)")
    }
}

private func diagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
