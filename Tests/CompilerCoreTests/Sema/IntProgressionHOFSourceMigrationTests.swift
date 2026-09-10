#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IntProgressionHOFSourceMigrationTests {
    @Test
    func noArgumentFirstAndLastAreSourceDefinitions() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let expectedReceiver = [
                interner.intern("kotlin"),
                interner.intern("ranges"),
                interner.intern("IntProgression"),
            ]

            for memberName in ["first", "last"] {
                let sourceSymbols = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("ranges"),
                    interner.intern(memberName),
                ]).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let sourceFileID = sema.symbols.sourceFileID(for: symbolID),
                          ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/ranges/RangeHOF.kt",
                          sema.symbols.externalLinkName(for: symbolID) == nil,
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.parameterTypes.isEmpty,
                          let receiverType = signature.receiverType,
                          case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                          let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
                    else {
                        return false
                    }
                    return receiverSymbol.fqName == expectedReceiver
                }

                #expect(
                    sourceSymbols.count == 1,
                    "Expected one source-backed IntProgression.\(memberName)(), got: \(sourceSymbols)"
                )
            }
        }
    }

    @Test
    func noArgumentCallsBindToSourceDefinitions() throws {
        let source = """
        fun probe() {
            val positive = IntProgression.fromClosedRange(2, 11, 3)
            val negative = 10 downTo -10 step 3
            positive.first()
            positive.last()
            negative.first()
            negative.last()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Expected IntProgression first/last calls to type-check: \(ctx.diagnostics.diagnostics)")
            let progressionOverlapWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-0102"
                    && $0.message.contains("IntProgression")
                    && ($0.message.contains("'first'") || $0.message.contains("'last'"))
            }
            #expect(
                progressionOverlapWarnings.isEmpty,
                "Expected retained IntProgression properties to avoid duplicate source-function warnings: \(progressionOverlapWarnings)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var seen = Set<String>()
            for offset in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(offset))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID)
                else { continue }
                let memberName = ctx.interner.resolve(callee)
                guard memberName == "first" || memberName == "last",
                      let binding = sema.bindings.callBinding(for: exprID)
                else { continue }

                let chosen = binding.chosenCallee
                #expect(sema.symbols.isSourceBackedSymbol(chosen), "Expected IntProgression.\(memberName)() to be source-backed")
                #expect(sema.symbols.externalLinkName(for: chosen) == nil)
                let signature = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(signature.parameterTypes.isEmpty)
                let receiver = try #require(signature.receiverType)
                let (_, receiverSymbol) = try #require(resolveClassTypeSymbol(receiver, sema: sema))
                #expect(
                    receiverSymbol.fqName == [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("ranges"),
                        ctx.interner.intern("IntProgression"),
                    ],
                    "Unexpected receiver for IntProgression.\(memberName)()"
                )
                seen.insert(memberName)
            }

            #expect(seen == ["first", "last"], "Missing source-backed calls: \(seen)")
        }
    }
}
#endif
