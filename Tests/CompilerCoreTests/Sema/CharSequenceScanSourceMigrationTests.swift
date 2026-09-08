#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CharSequenceScanSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringHOF.kt"

    @Test
    func scanFamilyDeclarationsAreSourceBacked() throws {
        let context = makeContextFromSource("fun noop() {}")
        try runSema(context)
        #expect(!context.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: context)))

        let sema = try #require(context.sema)
        let charSequenceSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "CharSequence"].map(context.interner.intern))
        )
        let packageFQName = ["kotlin", "text"].map(context.interner.intern)
        let expectedArities: [String: Int] = [
            "scan": 2,
            "scanIndexed": 2,
        ]

        for (name, arity) in expectedArities {
            let symbols = sema.symbols.lookupAll(fqName: packageFQName + [context.interner.intern(name)]).filter { id in
                guard let symbol = sema.symbols.symbol(id),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: id),
                      let signature = sema.symbols.functionSignature(for: id),
                      let receiverType = signature.receiverType,
                      case let .classType(receiver) = sema.types.kind(of: receiverType)
                else {
                    return false
                }
                return context.sourceManager.path(of: fileID) == sourcePath
                    && receiver.classSymbol == charSequenceSymbol
                    && signature.parameterTypes.count == arity
            }

            #expect(symbols.count == 1, "Expected one CharSequence.\(name) declaration, got \(symbols.count)")
            for symbolID in symbols {
                let symbol = try #require(sema.symbols.symbol(symbolID))
                #expect(symbol.flags.contains(.inlineFunction))
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
            }
        }
    }

    @Test
    func scanFamilyCallsBindToBundledSource() throws {
        let context = makeContextFromSource("""
        fun direct(source: CharSequence) {
            source.scan(0) { accumulator, value -> if (value == 'b') return; accumulator + value.code }
            source.scanIndexed(0) { index, accumulator, value ->
                if (index == 1) return
                accumulator + value.code
            }
        }
        fun safe(source: CharSequence?) {
            source?.scan(0) { accumulator, value -> if (value == 'b') return; accumulator + value.code }
            source?.scanIndexed(0) { index, accumulator, value ->
                if (index == 1) return
                accumulator + value.code
            }
        }
        fun named(source: CharSequence, seed: Int): Int {
            source.scan(initial = seed, operation = { accumulator, value ->
                if (value == 'b') return accumulator
                accumulator + value.code
            })
            source.scanIndexed(initial = seed, operation = { index, accumulator, value ->
                if (index == 1) return accumulator
                accumulator + value.code
            })
            return -1
        }
        """)
        try runSema(context)
        #expect(!context.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: context)))

        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let userFileID = try #require(context.sourceManager.fileIDs().first {
            context.sourceManager.origin(of: $0) == .user
        })
        let names = Set(["scan", "scanIndexed"])
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

        #expect(calls == 6, "Expected six direct, safe, and named CharSequence scan-family calls, got \(calls)")
    }
}

private func diagnosticSummary(in context: CompilationContext) -> String {
    context.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
#endif
