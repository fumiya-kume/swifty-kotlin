#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1078: the Set nominal declaration and its four built-in members are
/// bundled Kotlin source while the compatibility shell retains runtime links.
@Suite
struct SetSourceMigrationTests {
    private func makeSema() throws -> CompilationContext {
        let source = """
        fun inspect(values: Set<Int>, collection: Collection<Int>): Boolean {
            val iterator = values.iterator()
            return values.size >= 0 && values.isEmpty() && values.contains(1) &&
                values.containsAll(listOf(1)) &&
                collection.contains(1) && iterator.hasNext()
        }
        """
        var context: CompilationContext?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            context = ctx
        }
        return try #require(context)
    }

    @Test
    func setNominalIsSourceBackedWithKotlinVarianceAndCollectionSupertype() throws {
        let ctx = try makeSema()
        let sema = try #require(ctx.sema)
        let collections = ["kotlin", "collections"].map(ctx.interner.intern)
        let setSymbol = try #require(sema.symbols.lookup(fqName: collections + [ctx.interner.intern("Set")]))
        let collectionSymbol = try #require(sema.symbols.lookup(fqName: collections + [ctx.interner.intern("Collection")]))
        let setInfo = try #require(sema.symbols.symbol(setSymbol))
        let collectionInfo = try #require(sema.symbols.symbol(collectionSymbol))
        let sourceFileID = try #require(sema.symbols.sourceFileID(for: setSymbol))

        #expect(!setInfo.flags.contains(.synthetic))
        #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/collections/SetHOF.kt")
        #expect(setInfo.kind == .interface)
        #expect(sema.types.nominalTypeParameterVariances(for: setSymbol) == [.out])
        #expect(sema.symbols.directSupertypes(for: setSymbol) == [collectionSymbol])
        #expect(sema.symbols.supertypeTypeArgs(for: setSymbol, supertype: collectionSymbol).count == 1)

        // KSP-934 is source-backed on this master; KSP-948 shares its Collection supertype.
        #expect(!collectionInfo.flags.contains(.synthetic))
    }

    @Test
    func setMembersAreSourceBackedAndRetainOnlyRuntimeStorageLinks() throws {
        let ctx = try makeSema()
        let sema = try #require(ctx.sema)
        let collections = ["kotlin", "collections"].map(ctx.interner.intern)
        let setFQName = collections + [ctx.interner.intern("Set")]
        let sourcePath = "__bundled_kotlin/collections/SetHOF.kt"

        for member in ["contains", "isEmpty", "iterator", "size"] {
            let memberSymbol = try #require(
                sema.symbols.lookup(fqName: setFQName + [ctx.interner.intern(member)])
            )
            let memberInfo = try #require(sema.symbols.symbol(memberSymbol))
            let sourceFileID = try #require(sema.symbols.sourceFileID(for: memberSymbol))
            #expect(!memberInfo.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(memberSymbol))
            #expect(ctx.sourceManager.path(of: sourceFileID) == sourcePath)
            let expectedLink: String? = switch member {
            case "contains": "__kk_set_contains"
            case "isEmpty": "__kk_set_is_empty"
            case "iterator": "kk_list_iterator"
            case "size": "__kk_set_size"
            default: fatalError("unhandled Set member: \(member)")
            }
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == expectedLink)
        }

        let ast = try #require(ctx.ast)
        let containsAllCall = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "containsAll"
        })
        let chosenCallee = try #require(sema.bindings.callBinding(for: containsAllCall)?.chosenCallee)
        #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
        #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
    }
}
#endif
