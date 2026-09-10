#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1400: Validates that both CharSequence.slice overloads are provided by
/// the bundled StringSubstringSlice source and keep the CharSequence contract.
@Suite
struct CharSequenceSliceSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringSubstringSlice.kt"

    @Test
    func sliceFamilyDeclarationsAreSourceBacked() throws {
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
        let iterableSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "Iterable"].map(interner.intern))
        )
        let iterableIntType = sema.types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.invariant(sema.types.intType)],
            nullability: .nonNull
        )))

        let sliceSymbols = sema.symbols.lookupAll(
            fqName: ["kotlin", "text", "slice"].map(interner.intern)
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
                && signature.parameterTypes.count == 1
                && signature.returnType == charSequenceType
        }

        #expect(sliceSymbols.count == 2, "Expected two source-backed CharSequence.slice overloads")
        let parameterTypeNames = Set(sliceSymbols.compactMap { id -> String? in
            guard let signature = sema.symbols.functionSignature(for: id),
                  let parameter = signature.parameterTypes.first
            else {
                return nil
            }
            return sema.types.renderType(parameter)
        })
        #expect(parameterTypeNames.contains(sema.types.renderType(intRangeType)))
        #expect(parameterTypeNames.contains(sema.types.renderType(iterableIntType)))
        for symbolID in sliceSymbols {
            let symbol = try #require(sema.symbols.symbol(symbolID))
            #expect(!symbol.flags.contains(.inlineFunction))
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
        }
    }

    @Test
    func sliceFamilyCallsBindToCharSequenceSource() throws {
        let source = """
        fun rangeSlice(source: CharSequence): CharSequence = source.slice(1..3)
        fun iterableSlice(source: CharSequence, indices: Iterable<Int>): CharSequence = source.slice(indices)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: ctx)))

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let charSequenceSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "CharSequence"].map(ctx.interner.intern))
        )
        let charSequenceType = sema.types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, range) = ast.arena.expr(exprID),
                  ctx.interner.resolve(callee) == "slice",
                  !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            else {
                return nil
            }
            return exprID
        }
        #expect(calls.count == 2, "Expected both CharSequence.slice calls in the user source")
        for call in calls {
            let binding = try #require(sema.bindings.callBinding(for: call))
            let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))
            let fileID = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            #expect(ctx.sourceManager.path(of: fileID) == sourcePath)
            #expect(!chosen.flags.contains(.synthetic))
            #expect(!chosen.flags.contains(.inlineFunction))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
            #expect(sema.symbols.functionSignature(for: binding.chosenCallee)?.receiverType == charSequenceType)
        }
    }

    private func diagnosticSummary(in ctx: CompilationContext) -> String {
        ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
    }
}
#endif
