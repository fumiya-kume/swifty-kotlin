#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-TYPE-007 / KSP-486: Validates that `kotlin.text.MatchGroup` comes
/// from the bundled Kotlin source (`__bundled_kotlin/text/MatchResult.kt`) with
/// its `value: String` / `range: IntRange` constructor properties, and that
/// source-level access through `MatchResult.groups[..]` type-checks without
/// diagnostics.
@Suite
struct MatchGroupTypeTests {

    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner, CompilationContext)?

    // MARK: - Shared sema fixture

    private func sharedSema() throws -> (SemaModule, StringInterner, CompilationContext) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner, CompilationContext)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner, ctx)
        }
        let triple = try #require(result)
        Self._sharedSema = triple
        return triple
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

    // MARK: - 1. Class symbol comes from bundled Kotlin source

    @Test func testMatchGroupClassSymbolComesFromBundledSource() throws {
        let (sema, interner, ctx) = try sharedSema()
        let fq = ["kotlin", "text", "MatchGroup"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "kotlin.text.MatchGroup class symbol must be registered by sema"
        )
        let info = try #require(sema.symbols.symbol(sym))
        #expect(info.kind == .class, "MatchGroup should be registered with kind=class")
        #expect(
            sourcePath(for: sym, sema: sema, ctx: ctx)?.contains("__bundled_kotlin/text/MatchResult.kt") == true,
            "MatchGroup must be backed by the bundled Kotlin source"
        )
    }

    // KSP-1430: the Native MatchGroup constructor is a public source-backed
    // primary constructor with exactly (String, IntRange) parameters.
    @Test func testMatchGroupConstructorHasNativeSignature() throws {
        let (sema, interner, ctx) = try sharedSema()
        let matchGroupFQ = ["kotlin", "text", "MatchGroup"].map { interner.intern($0) }
        let matchGroupSymbol = try #require(sema.symbols.lookup(fqName: matchGroupFQ))
        let matchGroupType = sema.types.make(.classType(ClassType(
            classSymbol: matchGroupSymbol,
            args: [],
            nullability: .nonNull
        )))
        let intRangeFQ = ["kotlin", "ranges", "IntRange"].map { interner.intern($0) }
        let intRangeSymbol = try #require(sema.symbols.lookup(fqName: intRangeFQ))
        let intRangeType = sema.types.make(.classType(ClassType(
            classSymbol: intRangeSymbol,
            args: [],
            nullability: .nonNull
        )))

        let constructors = sema.symbols.lookupAll(
            fqName: matchGroupFQ + [interner.intern("<init>")]
        ).filter { sema.symbols.symbol($0)?.kind == .constructor }
        #expect(constructors.count == 1)
        let constructor = try #require(constructors.first)
        let info = try #require(sema.symbols.symbol(constructor))
        let signature = try #require(sema.symbols.functionSignature(for: constructor))

        #expect(info.visibility == .public)
        #expect(!info.flags.contains(.synthetic))
        #expect(sema.symbols.externalLinkName(for: constructor) == nil)
        #expect(sourcePath(for: constructor, sema: sema, ctx: ctx)?.contains("__bundled_kotlin/text/MatchResult.kt") == true)
        #expect(signature.receiverType == matchGroupType)
        #expect(signature.parameterTypes == [sema.types.stringType, intRangeType])
        #expect(signature.returnType == matchGroupType)
        #expect(signature.valueParameterHasDefaultValues == [false, false])
        #expect(signature.valueParameterIsVararg == [false, false])
    }

    // MARK: - 2. value / range are plain source properties (no runtime link)

    @Test func testMatchGroupPropertiesAreSourceBacked() throws {
        let (sema, interner, ctx) = try sharedSema()
        for propertyName in ["value", "range"] {
            let fq = ["kotlin", "text", "MatchGroup", propertyName].map { interner.intern($0) }
            let sym = try #require(
                sema.symbols.lookupAll(fqName: fq).first { sema.symbols.symbol($0)?.kind == .property },
                "MatchGroup.\(propertyName) property must be registered"
            )
            #expect(
                sema.symbols.externalLinkName(for: sym) == nil,
                "MatchGroup.\(propertyName) must not link to a runtime entry point"
            )
            #expect(
                sourcePath(for: sym, sema: sema, ctx: ctx)?.contains("__bundled_kotlin/text/MatchResult.kt") == true
            )
        }
    }

    // MARK: - 3. MatchGroupCollection comes from bundled Kotlin source

    @Test func testMatchGroupCollectionComesFromBundledSource() throws {
        let (sema, interner, ctx) = try sharedSema()
        let fq = ["kotlin", "text", "MatchGroupCollection"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "kotlin.text.MatchGroupCollection class symbol must be registered by sema"
        )
        #expect(
            sourcePath(for: sym, sema: sema, ctx: ctx)?.contains("__bundled_kotlin/text/MatchResult.kt") == true
        )
        let sizeFQ = fq + [interner.intern("size")]
        let sizeSymbol = try #require(
            sema.symbols.lookupAll(fqName: sizeFQ).first { sema.symbols.symbol($0)?.kind == .property }
        )
        #expect(sema.symbols.externalLinkName(for: sizeSymbol) == nil)
    }

    // MARK: - 4. Source-level usage of MatchGroup

    @Test func testMatchGroupAccessThroughMatchResultGroupsTypeChecks() throws {
        let ctx = makeContextFromSource("""
        fun firstGroupValue(input: String): String? {
            val regex = Regex("(a)(b)")
            val match = regex.find(input)
            val group: MatchGroup? = match?.groups?.get("a")
            return group?.value
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected MatchGroup access via MatchResult.groups to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - 5. Indexed access and range reads type-check

    @Test func testMatchGroupIndexedAccessAndRangeTypeCheck() throws {
        let ctx = makeContextFromSource("""
        fun groupSpan(input: String): Int {
            val match = Regex("(a)(b)").find(input) ?: return -1
            val group = match.groups[1] ?: return -1
            return group.range.first + match.groups.size
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected MatchGroupCollection indexed access to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
#endif
