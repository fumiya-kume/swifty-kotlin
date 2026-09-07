#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1195: BitSet members are source-backed and do not use synthetic runtime links.
@Suite
struct BitSetSourceMigrationTests {
    @Test
    func testBitSetMembersAreSourceBackedWithExactSurface() throws {
        let source = """
        @file:OptIn(kotlin.native.ObsoleteNativeApi::class)

        import kotlin.native.BitSet

        fun probe(bits: BitSet, other: BitSet) {
            bits.set(1)
            bits.set(2, 5)
            bits.set(0..1, false)
            bits.set(10, 12, false)
            bits.flip(4)
            bits.flip(5, 7)
            bits.flip(8..9)
            bits[4]
            bits.nextSetBit()
            bits.nextSetBit(5)
            bits.nextClearBit()
            bits.nextClearBit(5)
            bits.previousSetBit(20)
            bits.previousClearBit(4)
            bits.previousBit(20, true)
            bits.lastTrueIndex
            bits.isEmpty
            bits.size
            bits.toString()
            bits.hashCode()
            bits.equals(other)
            bits.intersects(other)
            bits.and(other)
            bits.or(other)
            bits.xor(other)
            bits.andNot(other)
            bits.clear(4)
            bits.clear(5, 7)
            bits.clear(8..9)
            bits.clear(0, 1)
            bits.clear()
            bits.size
        }
        """

        var result: CompilationContext?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = ctx
        }

        let ctx = try #require(result)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected BitSet member surface to type-check, got: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let bitSetFQName = ["kotlin", "native", "BitSet"].map(interner.intern)
        let bitSetID = try #require(sema.symbols.lookup(fqName: bitSetFQName))
        let bitSet = try #require(sema.symbols.symbol(bitSetID))
        #expect(bitSet.kind == .class)
        #expect(!bitSet.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(bitSetID))
        #expect(sourcePath(for: bitSetID, sema: sema, ctx: ctx)?.hasSuffix("native/BitSet/Stdlib.kt") == true)

        let functionCounts: [(name: String, count: Int)] = [
            ("and", 1),
            ("andNot", 1),
            ("clear", 4),
            ("equals", 1),
            ("flip", 3),
            ("get", 1),
            ("hashCode", 1),
            ("intersects", 1),
            ("nextClearBit", 1),
            ("nextSetBit", 1),
            ("or", 1),
            ("previousBit", 1),
            ("previousClearBit", 1),
            ("previousSetBit", 1),
            ("set", 3),
            ("toString", 1),
            ("xor", 1),
        ]

        for (name, expectedCount) in functionCounts {
            let symbols = sema.symbols.lookupAll(fqName: bitSetFQName + [interner.intern(name)]).filter {
                sema.symbols.symbol($0)?.kind == .function
            }
            #expect(symbols.count == expectedCount, "Expected \(expectedCount) BitSet.\(name) overload(s), got \(symbols.count)")
            for symbolID in symbols {
                #expect(sema.symbols.isSourceBackedSymbol(symbolID))
                #expect(!sema.symbols.symbol(symbolID)!.flags.contains(.synthetic))
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
                #expect(sourcePath(for: symbolID, sema: sema, ctx: ctx)?.hasSuffix("native/BitSet/Stdlib.kt") == true)
            }
        }

        for name in ["isEmpty", "lastTrueIndex", "size"] {
            let propertyID = try #require(
                sema.symbols.lookupAll(fqName: bitSetFQName + [interner.intern(name)]).first {
                    sema.symbols.symbol($0)?.kind == .property
                },
                "Expected BitSet.\(name) property"
            )
            #expect(sema.symbols.isSourceBackedSymbol(propertyID))
            #expect(!sema.symbols.symbol(propertyID)!.flags.contains(.synthetic))
            #expect(sema.symbols.externalLinkName(for: propertyID) == nil)
            #expect(sourcePath(for: propertyID, sema: sema, ctx: ctx)?.hasSuffix("native/BitSet/Stdlib.kt") == true)
            let expectedType = name == "size" || name == "lastTrueIndex"
                ? sema.types.intType
                : sema.types.booleanType
            #expect(sema.symbols.propertyType(for: propertyID) == expectedType)
            #expect(sema.symbols.symbol(propertyID)!.flags.contains(.mutable) == (name == "size"))
        }
    }

    private func sourcePath(
        for symbol: SymbolID,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> String? {
        let fileID = sema.symbols.sourceFileID(for: symbol)
            ?? sema.symbols.symbol(symbol)?.declSite?.start.file
            ?? sema.symbols.parentSymbol(for: symbol).flatMap { sema.symbols.sourceFileID(for: $0) }
        guard let fileID else { return nil }
        return ctx.sourceManager.path(of: fileID)
    }
}
#endif
