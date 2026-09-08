#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CharSequenceForSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringHOF.kt"

    @Test
    func forFamilyDeclarationsAreSourceBacked() throws {
        let context = makeContextFromSource("fun noop() {}")
        try runSema(context)
        #expect(!context.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: context)))

        let sema = try #require(context.sema)
        let charSequenceSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "CharSequence"].map(context.interner.intern))
        )
        let charSequenceType = sema.types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let packageFQName = ["kotlin", "text"].map(context.interner.intern)
        let expectedArities: [String: Int] = [
            "forEach": 1,
            "forEachIndexed": 1,
        ]

        for (name, arity) in expectedArities {
            let symbols = sema.symbols.lookupAll(fqName: packageFQName + [context.interner.intern(name)]).filter { id in
                guard let symbol = sema.symbols.symbol(id),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: id),
                      let signature = sema.symbols.functionSignature(for: id)
                else {
                    return false
                }
                return context.sourceManager.path(of: fileID) == sourcePath
                    && signature.receiverType == charSequenceType
                    && signature.parameterTypes.count == arity
            }

            #expect(symbols.count == 1, "Expected one CharSequence.(name) declaration, got (symbols.count)")
            for symbolID in symbols {
                let symbol = try #require(sema.symbols.symbol(symbolID))
                #expect(symbol.flags.contains(.inlineFunction))
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
                #expect(sema.symbols.functionSignature(for: symbolID)?.returnType == sema.types.unitType)
            }
        }
    }

    @Test
    func forFamilyCallsBindToBundledSource() throws {
        let context = makeContextFromSource("""
        fun direct(source: CharSequence) {
            source.forEach { if (it == 'b') return }
            source.forEachIndexed { index, _ -> if (index < 0) return@forEachIndexed }
        }
        fun safe(source: CharSequence?) {
            source?.forEach { if (it == 'b') return }
            source?.forEachIndexed { index, _ -> if (index < 0) return@forEachIndexed }
        }
        fun named(source: CharSequence, target: Char): Char {
            source.forEach(action = { if (it == target) return it })
            source.forEachIndexed(action = { index, value -> if (index == 1) return value })
            return '?'
        }
        """)
        try runSema(context)
        #expect(!context.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: context)))

        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let userFileID = try #require(context.sourceManager.fileIDs().first {
            context.sourceManager.origin(of: $0) == .user
        })
        let names = Set(["forEach", "forEachIndexed"])
        var calls = 0

        for index in ast.arena.exprs.indices {
            let expressionID = ExprID(rawValue: Int32(index))
            guard let expression = ast.arena.expr(expressionID),
                  ast.arena.exprRange(expressionID)?.start.file == userFileID
            else {
                continue
            }

            let calleeName: InternedString
            switch expression {
            case let .memberCall(_, name, _, _, _), let .safeMemberCall(_, name, _, _, _):
                calleeName = name
            default:
                continue
            }

            guard names.contains(context.interner.resolve(calleeName)),
                  let binding = sema.bindings.callBinding(for: expressionID)
            else {
                continue
            }

            calls += 1
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            let fileID = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            #expect(context.sourceManager.path(of: fileID) == sourcePath)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(symbol.flags.contains(.inlineFunction))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
        }

        #expect(calls == 6, "Expected six direct, safe, and named CharSequence for-family calls, got (calls)")
    }
}

private func diagnosticSummary(in context: CompilationContext) -> String {
    context.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
#endif
