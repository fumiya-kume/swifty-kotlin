#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-815: Char companion constants are bundled Kotlin source extensions,
/// not synthetic members or runtime-linked declarations.
@Suite
struct CharCompanionSourceMigrationTests {
    @Test
    func constantsAreSourceBackedAndUnlinked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected Char companion constants to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let sema = try #require(ctx.sema)
            let charSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("Char"),
            ]))
            let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: charSymbol))
            let companionType = sema.types.make(.classType(ClassType(
                classSymbol: companionSymbol,
                args: [],
                nullability: .nonNull
            )))
            let expected: [(name: String, type: TypeID)] = [
                ("MAX_CODE_POINT", sema.types.intType),
                ("MAX_HIGH_SURROGATE", sema.types.charType),
                ("MAX_LOW_SURROGATE", sema.types.charType),
                ("MAX_RADIX", sema.types.intType),
                ("MAX_SURROGATE", sema.types.charType),
                ("MAX_VALUE", sema.types.charType),
                ("MIN_CODE_POINT", sema.types.intType),
                ("MIN_HIGH_SURROGATE", sema.types.charType),
                ("MIN_LOW_SURROGATE", sema.types.charType),
                ("MIN_RADIX", sema.types.intType),
                ("MIN_SUPPLEMENTARY_CODE_POINT", sema.types.intType),
                ("MIN_SURROGATE", sema.types.charType),
                ("MIN_VALUE", sema.types.charType),
                ("SIZE_BITS", sema.types.intType),
                ("SIZE_BYTES", sema.types.intType),
            ]

            for item in expected {
                let propertyFQName = [ctx.interner.intern("kotlin"), ctx.interner.intern(item.name)]
                let property = try #require(sema.symbols.lookupAll(fqName: propertyFQName).first { symbolID in
                    guard sema.symbols.symbol(symbolID)?.kind == .property,
                          sema.symbols.propertyType(for: symbolID) == item.type,
                          sema.symbols.extensionPropertyReceiverType(for: symbolID) == companionType
                    else {
                        return false
                    }
                    return true
                }, "Expected Char.Companion.\(item.name) source property")

                let symbol = try #require(sema.symbols.symbol(property))
                #expect(!symbol.flags.contains(.synthetic))
                #expect(sema.symbols.isSourceBackedSymbol(property))
                #expect(sema.symbols.externalLinkName(for: property) == nil)
                let sourceFileID = try #require(sema.symbols.sourceFileID(for: property))
                #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/Char/Companion/Companion.kt")

                let getter = try #require(sema.symbols.extensionPropertyGetterAccessor(for: property))
                #expect(sema.symbols.isSourceBackedSymbol(getter))
                #expect(sema.symbols.externalLinkName(for: getter) == nil)
            }
        }
    }
}
#endif
