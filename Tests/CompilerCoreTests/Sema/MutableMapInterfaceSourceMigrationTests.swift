@testable import CompilerCore
import Testing

/// KSP-946: MutableMap's nominal declaration is source-backed while its
/// mutation and query members remain compiler/runtime residuals.
@Suite
struct MutableMapInterfaceSourceMigrationTests {
    @Test
    func mutableMapInterfaceUsesSourceDeclarationWithTargetVariance() throws {
        let ctx = makeContextFromSource(
            """
            fun probe(values: MutableMap<String, Int>): MutableMap<String, Int> = values
            """
        )
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let mutableMapFQName = ["kotlin", "collections", "MutableMap"].map(interner.intern)
        let mutableMapSymbol = try #require(sema.symbols.lookup(fqName: mutableMapFQName))
        let mutableMapInfo = try #require(sema.symbols.symbol(mutableMapSymbol))
        #expect(mutableMapInfo.kind == .interface)
        #expect(!mutableMapInfo.flags.contains(.synthetic))

        let sourceFile = try #require(sema.symbols.sourceFileID(for: mutableMapSymbol))
        #expect(ctx.sourceManager.path(of: sourceFile) == "__bundled_kotlin/collections/MutableMap.kt")
        #expect(sema.types.nominalTypeParameterVariances(for: mutableMapSymbol) == [.invariant, .invariant])

        let typeParameters = sema.types.nominalTypeParameterSymbols(for: mutableMapSymbol)
        #expect(typeParameters.count == 2)
        #expect(sema.symbols.symbol(typeParameters[0])?.name == interner.intern("K"))
        #expect(sema.symbols.symbol(typeParameters[1])?.name == interner.intern("V"))

        let mapSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "Map"].map(interner.intern))
        )
        #expect(sema.symbols.directSupertypes(for: mutableMapSymbol) == [mapSymbol])
    }

    @Test
    func mutableMapRetainsResidualMutationMemberLinks() throws {
        let ctx = makeContextFromSource(
            """
            fun mutate(values: MutableMap<String, Int>): MutableMap<String, Int> {
                values["present"] = 1
                values.put("present", 2)
                values.remove("missing")
                values.clear()
                return values
            }
            """
        )
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let mutableMapFQName = ["kotlin", "collections", "MutableMap"].map(interner.intern)
        let mutableMapSymbol = try #require(sema.symbols.lookup(fqName: mutableMapFQName))
        let expectedLinks: [(name: String, link: String)] = [
            ("put", "__kk_mutable_map_put"),
            ("remove", "__kk_mutable_map_remove"),
            ("clear", "__kk_mutable_map_clear"),
        ]
        for expected in expectedLinks {
            let memberFQName = mutableMapFQName + [interner.intern(expected.name)]
            let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
            #expect(sema.symbols.parentSymbol(for: memberSymbol) == mutableMapSymbol)
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == expected.link)
        }
    }
}
