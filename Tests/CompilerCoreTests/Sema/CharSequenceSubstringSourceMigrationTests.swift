@testable import CompilerCore
import Testing

/// KSP-1403: validates the CharSequence substring overloads against the
/// Kotlin 2.3.10 source surface and the bundled source binding path.
@Suite
struct CharSequenceSubstringSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringSubstringSlice.kt"

    @Test
    func overloadsHaveExactSourceBackedSignatures() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: substringDiagnosticSummary(in: ctx)))

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
        let substringFQName = ["kotlin", "text", "substring"].map(interner.intern)
        let sourceSymbols = sema.symbols.lookupAll(fqName: substringFQName).filter { symbolID in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  !symbol.flags.contains(.synthetic),
                  let fileID = sema.symbols.sourceFileID(for: symbolID),
                  ctx.sourceManager.path(of: fileID) == sourcePath,
                  let signature = sema.symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == charSequenceType
        }

        let scalar = try #require(sourceSymbols.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.parameterTypes == [sema.types.intType, sema.types.intType]
        })
        let scalarSignature = try #require(sema.symbols.functionSignature(for: scalar))
        #expect(scalarSignature.returnType == sema.types.stringType)
        #expect(scalarSignature.valueParameterHasDefaultValues == [false, true])
        #expect(sema.symbols.symbol(scalar)?.flags.contains(.inlineFunction) == true)
        #expect(sema.symbols.externalLinkName(for: scalar) == nil)

        let range = try #require(sourceSymbols.first { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.parameterTypes == [intRangeType]
        })
        let rangeSignature = try #require(sema.symbols.functionSignature(for: range))
        #expect(rangeSignature.returnType == sema.types.stringType)
        #expect(rangeSignature.valueParameterHasDefaultValues == [false])
        #expect(sema.symbols.symbol(range)?.flags.contains(.inlineFunction) == false)
        #expect(sema.symbols.externalLinkName(for: range) == nil)
        #expect(sourceSymbols.count == 2)
    }

    @Test
    func callsBindAcrossCharSequenceAndStringReceivers() throws {
        let source = """
        fun probe(source: CharSequence, text: String, builder: StringBuilder): String {
            val fromIndex = source.substring(1)
            val bounded = source.substring(startIndex = 1, endIndex = 3)
            val range = source.substring(1..3)
            val namedRange = source.substring(range = 1..3)
            val stringFromIndex = text.substring(1)
            val stringBounded = text.substring(1, 3)
            val stringRange = text.substring(1..3)
            val builderBounded = (builder as CharSequence).substring(1, 3)
            val builderRange = builder.substring(1..3)
            return fromIndex + bounded + range + namedRange + stringFromIndex
                + stringBounded + stringRange + builderBounded + builderRange
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: substringDiagnosticSummary(in: ctx)))

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let intRangeSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "ranges", "IntRange"].map(ctx.interner.intern))
        )
        let intRangeType = sema.types.make(.classType(ClassType(
            classSymbol: intRangeSymbol,
            args: [],
            nullability: .nonNull
        )))
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        var calls: [(SymbolID, [TypeID])] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, range) = ast.arena.expr(exprID),
                  range.start.file == userFileID,
                  ctx.interner.resolve(callee) == "substring",
                  let binding = sema.bindings.callBinding(for: exprID),
                  let signature = sema.symbols.functionSignature(for: binding.chosenCallee)
            else {
                continue
            }
            let symbolFileID = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            #expect(ctx.sourceManager.path(of: symbolFileID) == sourcePath)
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
            calls.append((binding.chosenCallee, signature.parameterTypes))
        }

        #expect(calls.count == 9, "Expected nine source-backed substring calls")
        #expect(calls.filter { $0.1 == [intRangeType] }.count == 4, "Expected four IntRange calls")
        #expect(calls.filter { $0.1.count == 2 }.count == 4, "Expected four scalar calls")
    }

    @Test
    func concreteMemberSubstringWinsOverVisibleExtension() throws {
        let source = """
        class MemberRange(private val value: String): CharSequence {
            override val length: Int get() = value.length
            override fun get(index: Int): Char = value[index]
            override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
                value.substring(startIndex, endIndex)
            fun substring(range: IntRange): String = "member"
        }

        fun MemberRange.substring(range: IntRange): String = "extension"

        fun probe(value: MemberRange): String = value.substring(1..3)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: substringDiagnosticSummary(in: ctx)))

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        let memberRangeSymbol = try #require(
            sema.symbols.lookup(fqName: [ctx.interner.intern("MemberRange")])
        )
        // Select the reachable probe body instead of scanning the arena: Sema
        // may retain orphan expressions from contextual re-inference.
        let probeBody = try #require(ast.files.first(where: { $0.fileID == userFileID })?.topLevelDecls.compactMap { declID -> ExprID? in
            guard case let .funDecl(function) = ast.arena.decl(declID),
                  ctx.interner.resolve(function.name) == "probe"
            else {
                return nil
            }
            switch function.body {
            case let .expr(exprID, _): return exprID
            case let .block(statements, _): return statements.last
            case .unit: return nil
            }
        }.first)
        let chosen = try #require(sema.bindings.callBinding(for: probeBody)?.chosenCallee)
        #expect(sema.symbols.parentSymbol(for: chosen) == memberRangeSymbol)
    }
}

private func substringDiagnosticSummary(in ctx: CompilationContext) -> String {
    ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
