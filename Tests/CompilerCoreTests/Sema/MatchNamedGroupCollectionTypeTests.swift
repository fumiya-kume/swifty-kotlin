#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct MatchNamedGroupCollectionTypeTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner, CompilationContext)?

    private func sharedSema() throws -> (SemaModule, StringInterner, CompilationContext) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner, CompilationContext)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner, ctx)
        }
        return try #require(result)
    }

    private func sourcePath(
        for symbol: SymbolID,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> String? {
        let fileID = sema.symbols.sourceFileID(for: symbol)
            ?? sema.symbols.symbol(symbol)?.declSite?.start.file
        guard let fileID else { return nil }
        return ctx.sourceManager.path(of: fileID)
    }

    @Test func testInterfaceAndNamedAccessorAreSourceBacked() throws {
        let (sema, interner, ctx) = try sharedSema()
        let namedFQName = ["kotlin", "text", "MatchNamedGroupCollection"].map(interner.intern)
        let namedSymbol = try #require(sema.symbols.lookup(fqName: namedFQName))
        let namedInfo = try #require(sema.symbols.symbol(namedSymbol))

        #expect(namedInfo.kind == .interface)
        #expect(!namedInfo.flags.contains(.synthetic))
        #expect(
            sourcePath(for: namedSymbol, sema: sema, ctx: ctx) ==
                "__bundled_kotlin/text/MatchNamedGroupCollection/MatchNamedGroupCollection.kt"
        )

        let matchGroupCollectionFQName = ["kotlin", "text", "MatchGroupCollection"].map(interner.intern)
        let matchGroupCollectionSymbol = try #require(
            sema.symbols.lookup(fqName: matchGroupCollectionFQName)
        )
        let matchGroupCollectionInfo = try #require(
            sema.symbols.symbol(matchGroupCollectionSymbol)
        )
        #expect(matchGroupCollectionInfo.kind == .interface)
        #expect(!matchGroupCollectionInfo.flags.contains(.synthetic))
        #expect(
            sema.symbols.directSupertypes(for: namedSymbol).contains(matchGroupCollectionSymbol),
            "MatchNamedGroupCollection must extend MatchGroupCollection"
        )

        let matchGroupFQName = ["kotlin", "text", "MatchGroup"].map(interner.intern)
        let matchGroupSymbol = try #require(sema.symbols.lookup(fqName: matchGroupFQName))
        let matchGroupType = sema.types.make(.classType(ClassType(
            classSymbol: matchGroupSymbol,
            args: [],
            nullability: .nonNull
        )))
        let member = try #require(
            sema.symbols.lookupAll(fqName: namedFQName + [interner.intern("get")])
                .first { sema.symbols.symbol($0)?.kind == .function }
        )
        let signature = try #require(sema.symbols.functionSignature(for: member))
        #expect(signature.receiverType == sema.types.make(.classType(ClassType(
            classSymbol: namedSymbol,
            args: [],
            nullability: .nonNull
        ))))
        #expect(signature.parameterTypes == [sema.types.stringType])
        #expect(signature.returnType == sema.types.makeNullable(matchGroupType))
        #expect(sema.symbols.externalLinkName(for: member) == nil)
        #expect(!sema.symbols.symbol(member)!.flags.contains(.synthetic))
        #expect(sourcePath(for: member, sema: sema, ctx: ctx)?.contains("MatchNamedGroupCollection.kt") == true)
    }

    @Test func testNamedAccessorTypeChecksThroughInterfaceReceiver() throws {
        var result: CompilationContext?
        try withTemporaryFile(contents: """
            fun readNamedGroup(collection: MatchNamedGroupCollection, name: String): MatchGroup? {
                return collection[name]
            }
            """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        #expect(
            ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty,
            "MatchNamedGroupCollection.get(String) should type-check through an interface receiver"
        )
    }
}
#endif
