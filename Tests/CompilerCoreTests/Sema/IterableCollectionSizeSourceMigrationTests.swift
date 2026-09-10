#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct IterableCollectionSizeSourceMigrationTests {
    @Test
    func collectionSizeHelpersArePublishedInternalBundledDeclarations() throws {
        let source = """
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        fun probe(values: Iterable<Int>): Int {
            return (values.collectionSizeOrNull() ?: -1) +
                values.collectionSizeOrDefault(7)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected collection-size helpers to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try #require(ctx.sema)
        let packageFQName = ["kotlin", "collections"].map(ctx.interner.intern)
        let sourcePath = "__bundled_kotlin/collections/Iterables.kt"
        let expected: [(name: String, parameterTypes: [TypeID], returnType: TypeID)] = [
            ("collectionSizeOrNull", [], sema.types.makeNullable(sema.types.intType)),
            ("collectionSizeOrDefault", [sema.types.intType], sema.types.intType),
        ]

        for item in expected {
            let symbols = sema.symbols.lookupAll(
                fqName: packageFQName + [ctx.interner.intern(item.name)]
            ).filter { symbolID in
                guard let fileID = sema.symbols.sourceFileID(for: symbolID) else { return false }
                return ctx.sourceManager.path(of: fileID) == sourcePath
            }

            #expect(symbols.count == 1, "Expected one bundled source declaration for \(item.name)")
            let symbolID = try #require(symbols.first)
            let symbol = try #require(sema.symbols.symbol(symbolID))
            let signature = try #require(sema.symbols.functionSignature(for: symbolID))

            #expect(symbol.kind == .function)
            #expect(symbol.visibility == .internal)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(symbolID))
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
            #expect(
                sema.symbols.annotations(for: symbolID).contains {
                    KnownCompilerAnnotation.publishedApi.matches($0.annotationFQName)
                }
            )
            #expect(signature.receiverType != nil)
            #expect(signature.parameterTypes == item.parameterTypes)
            #expect(signature.returnType == item.returnType)
        }
    }
}
#endif
