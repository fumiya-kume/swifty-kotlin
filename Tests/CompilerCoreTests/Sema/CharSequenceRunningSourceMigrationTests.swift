#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CharSequenceRunningSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringHOF.kt"

    @Test
    func runningFamilyDeclarationsAreSourceBacked() throws {
        let context = makeContextFromSource("fun noop() {}")
        try runSema(context)
        #expect(!context.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: context)))

        let sema = try #require(context.sema)
        let charSequenceSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "CharSequence"].map(context.interner.intern))
        )
        let packageFQName = ["kotlin", "text"].map(context.interner.intern)
        let expectedArities: [String: Int] = [
            "runningFold": 2,
            "runningFoldIndexed": 2,
            "runningReduce": 1,
            "runningReduceIndexed": 1,
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
    func runningFamilyCallsBindToBundledSource() throws {
        let context = makeContextFromSource("""
        fun direct(source: CharSequence) {
            source.runningFold(0) { accumulator, value -> if (value == 'b') return; accumulator + value.code }
            source.runningFoldIndexed(0) { index, accumulator, value ->
                if (index == 1) return
                accumulator + value.code
            }
            source.runningReduce { accumulator, value -> if (value == 'b') return; accumulator }
            source.runningReduceIndexed { index, accumulator, value ->
                if (index == 1) return
                accumulator
            }
        }
        fun safe(source: CharSequence?) {
            source?.runningFold(0) { accumulator, value -> if (value == 'b') return; accumulator + value.code }
            source?.runningFoldIndexed(0) { index, accumulator, value ->
                if (index == 1) return
                accumulator + value.code
            }
            source?.runningReduce { accumulator, value -> if (value == 'b') return; accumulator }
            source?.runningReduceIndexed { index, accumulator, value ->
                if (index == 1) return
                accumulator
            }
        }
        fun named(source: CharSequence, seed: Int): Int {
            source.runningFold(initial = seed, operation = { accumulator, value ->
                if (value == 'b') return accumulator
                accumulator + value.code
            })
            source.runningFoldIndexed(initial = seed, operation = { index, accumulator, value ->
                if (index == 1) return accumulator
                accumulator + value.code
            })
            source.runningReduce(operation = { accumulator, value ->
                if (value == 'b') return value
                accumulator
            })
            source.runningReduceIndexed(operation = { index, accumulator, value ->
                if (index == 1) return value
                accumulator
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
        let names = Set(["runningFold", "runningFoldIndexed", "runningReduce", "runningReduceIndexed"])
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

        #expect(calls == 12, "Expected twelve direct, safe, and named CharSequence running-family calls, got \(calls)")
    }
}

private func diagnosticSummary(in context: CompilationContext) -> String {
    context.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
#endif
