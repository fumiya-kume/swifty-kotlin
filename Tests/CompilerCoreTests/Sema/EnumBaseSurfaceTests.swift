#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct EnumBaseSurfaceTests {
    private static nonisolated(unsafe) var _sharedSema: (CompilationContext, SemaModule, StringInterner)?

    private func sharedSema() throws -> (CompilationContext, SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (CompilationContext, SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            result = try (ctx, #require(ctx.sema), ctx.interner)
        }
        let sema = try #require(result)
        Self._sharedSema = sema
        return sema
    }

    @Test
    func testEnumConstructorAndCompanionAreSourceBacked() throws {
        let (ctx, sema, interner) = try sharedSema()
        let enumFQName = ["kotlin", "Enum"].map(interner.intern)
        let enumSourceFileID = try #require(ctx.sourceManager.fileID(forPath: "__bundled_kotlin/Enum.kt"))
        let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))
        let enumInfo = try #require(sema.symbols.symbol(enumSymbol))
        #expect(enumInfo.kind == .class)
        #expect(enumInfo.flags.contains(.abstractType))
        #expect(sema.types.nominalTypeParameterVariances(for: enumSymbol) == [.invariant])
        #expect(sema.symbols.sourceFileID(for: enumSymbol) == enumSourceFileID)

        let constructor = try #require(
            sema.symbols.lookup(fqName: enumFQName + [interner.intern("<init>")])
        )
        let constructorInfo = try #require(sema.symbols.symbol(constructor))
        #expect(constructorInfo.kind == .constructor)
        #expect(constructorInfo.visibility == .protected)
        let constructorSignature = try #require(sema.symbols.functionSignature(for: constructor))
        #expect(constructorSignature.parameterTypes == [sema.types.stringType, sema.types.intType])

        let companion = try #require(sema.symbols.companionObjectSymbol(for: enumSymbol))
        let companionInfo = try #require(sema.symbols.symbol(companion))
        #expect(companionInfo.kind == .object)
        #expect(!companionInfo.flags.contains(.synthetic))
        #expect(sema.symbols.sourceFileID(for: companion) == enumSourceFileID)
    }

    @Test
    func testEnumMembersAreSourceBackedAndKeepRuntimeBridges() throws {
        let (ctx, sema, interner) = try sharedSema()
        let enumFQName = ["kotlin", "Enum"].map(interner.intern)
        let enumSourceFileID = try #require(ctx.sourceManager.fileID(forPath: "__bundled_kotlin/Enum.kt"))

        let functionLinks = [
            "compareTo": "__kk_comparable_compareTo",
            "equals": "kk_any_member_equals",
            "hashCode": "kk_any_member_hashCode",
            "toString": "kk_any_member_to_string",
        ]
        for (name, expectedLink) in functionLinks {
            let symbol = try #require(
                sema.symbols.lookupAll(fqName: enumFQName + [interner.intern(name)])
                    .first { sema.symbols.symbol($0)?.kind == .function }
            )
            let info = try #require(sema.symbols.symbol(symbol))
            #expect(!info.flags.contains(.synthetic), "Enum.\(name) must be source-backed")
            #expect(sema.symbols.sourceFileID(for: symbol) == enumSourceFileID)
            #expect(sema.symbols.externalLinkName(for: symbol) == expectedLink)
        }

        let propertyTypes = [
            "name": sema.types.stringType,
            "ordinal": sema.types.intType,
        ]
        for (name, expectedType) in propertyTypes {
            let symbols = sema.symbols.lookupAll(fqName: enumFQName + [interner.intern(name)])
                .filter { sema.symbols.symbol($0)?.kind == .property }
            #expect(symbols.count == 1, "Enum.\(name) must have one source-backed property")
            let symbol = try #require(symbols.first)
            let info = try #require(sema.symbols.symbol(symbol))
            #expect(!info.flags.contains(.synthetic), "Enum.\(name) must be source-backed")
            #expect(sema.symbols.sourceFileID(for: symbol) == enumSourceFileID)
            #expect(sema.symbols.propertyType(for: symbol) == expectedType)
        }
    }
}
#endif
