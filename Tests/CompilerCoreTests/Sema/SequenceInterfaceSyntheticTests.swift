@testable import CompilerCore
import Testing

@Suite
struct SequenceInterfaceSyntheticTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        let pair = try makeSema()
        Self._sharedSema = pair
        return pair
    }

    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, Comment(rawValue: "Expected Sequence interface surface to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testSequenceInterfaceSurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let sequencePackage = ["kotlin", "sequences"].map { interner.intern($0) }
        let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

        let sequenceSymbol = try #require(sema.symbols.lookup(
            fqName: sequencePackage + [interner.intern("Sequence")]
        ))
        let iteratorSymbol = try #require(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("Iterator")]
        ))
        let sequenceInfo = try #require(sema.symbols.symbol(sequenceSymbol))
        let iteratorInfo = try #require(sema.symbols.symbol(iteratorSymbol))
        #expect(sequenceInfo.kind == .interface)
        #expect(!sequenceInfo.flags.contains(.synthetic))
        #expect(iteratorInfo.kind == .interface)
        #expect(!iteratorInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(iteratorSymbol))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: sequenceSymbol)
        #expect(typeParams.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: sequenceSymbol) == [.out])
        #expect(sema.types.nominalTypeParameterSymbols(for: iteratorSymbol).count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: iteratorSymbol) == [.out])

        for memberName in ["hasNext", "next"] {
            let member = try #require(sema.symbols.lookup(
                fqName: collectionsPackage + [interner.intern("Iterator"), interner.intern(memberName)]
            ))
            #expect(sema.symbols.symbol(member)?.flags.contains(.operatorFunction) == true)
            #expect(sema.symbols.isSourceBackedSymbol(member))
            #expect(sema.symbols.externalLinkName(for: member) == "kk_iterator_\(memberName)")
        }

        let elementType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let iteratorType = sema.types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))

        let iteratorMember = try #require(sema.symbols.lookup(
            fqName: sequencePackage + [interner.intern("Sequence"), interner.intern("iterator")]
        ))
        #expect(sema.symbols.symbol(iteratorMember)?.flags.contains(.operatorFunction) == true)
        let signature = try #require(sema.symbols.functionSignature(for: iteratorMember))
        let signatureReceiver = try #require(signature.receiverType)
        #expect(sema.types.isSubtype(signatureReceiver, receiverType) && sema.types.isSubtype(receiverType, signatureReceiver))
        #expect(signature.parameterTypes == [])
        #expect(sema.types.isSubtype(signature.returnType, iteratorType) && sema.types.isSubtype(iteratorType, signature.returnType))
        #expect(signature.typeParameterSymbols == typeParams)
        #expect(signature.classTypeParameterCount == 1)
    }

    @Test func testSequenceIteratorResolvesInSource() throws {
        let source = """
        import kotlin.collections.Iterator
        import kotlin.sequences.Sequence

        fun <T> iteratorOf(values: Sequence<T>): Iterator<T> =
            values.iterator()
        """

        _ = try makeSema(source: source)
    }

    @Test func testSequenceOrEmptyAndIteratorResolveToBundledSources() throws {
        let source = """
        fun normalize(input: Sequence<Int>?): Sequence<Int> = input.orEmpty()
        fun first(input: Sequence<Int>): Int = input.iterator().next()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                Comment(rawValue: "Expected source-backed Sequence calls to resolve cleanly, got: \(diagnostics)")
            )

            let sema = try #require(ctx.sema)
            let sequencePackage = ["kotlin", "sequences"].map(ctx.interner.intern)
            let iteratorFQName = sequencePackage + [
                ctx.interner.intern("Sequence"), ctx.interner.intern("iterator")
            ]
            let iteratorSources = sema.symbols.lookupAll(fqName: iteratorFQName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else { return false }
                return !symbol.flags.contains(.synthetic) && symbol.declSite != nil
            }
            #expect(iteratorSources.count == 1, "Expected one bundled Sequence.iterator declaration")
            let iteratorSymbol = try #require(iteratorSources.first)
            #expect(sema.symbols.externalLinkName(for: iteratorSymbol) == nil)

            let orEmptyFQName = sequencePackage + [ctx.interner.intern("orEmpty")]
            let orEmptySources = sema.symbols.lookupAll(fqName: orEmptyFQName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else { return false }
                return symbol.kind == .function
                    && !symbol.flags.contains(.synthetic)
                    && symbol.declSite != nil
            }
            #expect(orEmptySources.count == 1, "Expected one bundled Sequence.orEmpty declaration")
            let orEmptySymbol = try #require(orEmptySources.first)
            #expect(sema.symbols.externalLinkName(for: orEmptySymbol) == nil)

            let ast = try #require(ctx.ast)
            func memberCallIDs(named name: String) -> [ExprID] {
                ast.arena.exprs.indices.compactMap { index -> ExprID? in
                    let exprID = ExprID(rawValue: Int32(index))
                    guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID) else {
                        return nil
                    }
                    return ctx.interner.resolve(callee) == name ? exprID : nil
                }
            }

            let orEmptyCall = try #require(memberCallIDs(named: "orEmpty").last)
            let orEmptyBinding = try #require(sema.bindings.callBinding(for: orEmptyCall))
            #expect(orEmptyBinding.chosenCallee == orEmptySymbol)
            #expect(sema.symbols.isSourceBackedSymbol(orEmptyBinding.chosenCallee))

            let iteratorCall = try #require(memberCallIDs(named: "iterator").last)
            let iteratorBinding = try #require(sema.bindings.callBinding(for: iteratorCall))
            #expect(iteratorBinding.chosenCallee == iteratorSymbol)
            #expect(sema.symbols.isSourceBackedSymbol(iteratorBinding.chosenCallee))
        }
    }
}
