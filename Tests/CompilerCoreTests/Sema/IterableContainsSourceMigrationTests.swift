#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct IterableContainsSourceMigrationTests {
    @Test
    func iterableContainsUsesBundledSourceWithoutReplacingConcreteOwners() throws {
        let source = """
        class ProbeIterable<T>(private val values: List<T>) : Iterable<T> {
            override fun iterator(): Iterator<T> = values.iterator()
        }

        fun probe(
            iterable: Iterable<Int>,
            custom: ProbeIterable<Int>,
            list: List<Int>,
            collection: Collection<Int>,
            set: Set<Int>
        ) {
            iterable.contains(1)
            2 in iterable
            custom.contains(3)
            4 !in custom
            list.contains(1)
            collection.contains(1)
            set.contains(1)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Expected Iterable.contains to type-check, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let containsFQName = ["kotlin", "collections", "contains"].map(ctx.interner.intern)
            let iterableFQName = ["kotlin", "collections", "Iterable"].map(ctx.interner.intern)
            let sourceSymbol = try #require(sema.symbols.lookupAll(fqName: containsFQName).first { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      symbol.flags.contains(.operatorFunction),
                      !symbol.flags.contains(.synthetic),
                      sema.symbols.externalLinkName(for: symbolID) == nil,
                      let fileID = sema.symbols.sourceFileID(for: symbolID),
                      ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/Iterables.kt",
                      let receiverType = sema.symbols.functionSignature(for: symbolID)?.receiverType,
                      case let .classType(receiverClass) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
                else {
                    return false
                }
                return sema.symbols.symbol(receiverClass.classSymbol)?.fqName == iterableFQName
            })

            let signature = try #require(sema.symbols.functionSignature(for: sourceSymbol))
            #expect(
                signature.typeParameterSymbols.count == 1,
                "Unexpected type parameters: \(signature.typeParameterSymbols.compactMap { sema.symbols.symbol($0)?.fqName.map(ctx.interner.resolve) })"
            )
            #expect(signature.parameterTypes.count == 1)
            #expect(signature.returnType == sema.types.booleanType)

            let declarationRange = try #require(sema.symbols.symbol(sourceSymbol)?.declSite)
            let declarationSource = ctx.sourceManager.slice(declarationRange)
            #expect(declarationSource.contains("@kotlin.internal.OnlyInputTypes"))
            #expect(declarationSource.contains("this is Collection<*>"))
            #expect(declarationSource.contains("indexOf(element) >= 0"))

            let userExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path
                else {
                    return nil
                }
                return exprID
            }
            let userBindings = userExprIDs.compactMap { sema.bindings.callBinding(for: $0) }
            #expect(userBindings.filter { $0.chosenCallee == sourceSymbol }.count == 4)

            let retainedLinks = Set(userBindings.compactMap {
                sema.symbols.externalLinkName(for: $0.chosenCallee)
            })
            #expect(retainedLinks.contains("kk_op_contains"))
            #expect(retainedLinks.contains("__kk_set_contains"))
        }
    }
}
#endif
