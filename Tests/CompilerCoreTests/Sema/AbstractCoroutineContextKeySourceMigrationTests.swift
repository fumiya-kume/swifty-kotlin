#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct AbstractCoroutineContextKeySourceMigrationTests {
    @Test
    func testClassAndConstructorAreBackedByBundledSource() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            let errorSummary = errors.map { "\($0.code): \($0.message)" }.joined(separator: "\n")
            #expect(
                errors.isEmpty,
                "Expected bundled AbstractCoroutineContextKey.kt to type-check, got: \(errorSummary)"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let classFQName = ["kotlin", "coroutines", "AbstractCoroutineContextKey"].map(interner.intern)
            let classSymbol = try #require(
                sema.symbols.lookupAll(fqName: classFQName).first { symbolID in
                    sema.symbols.symbol(symbolID)?.kind == .class
                }
            )
            let classInfo = try #require(sema.symbols.symbol(classSymbol))

            #expect(!classInfo.flags.contains(.synthetic))
            #expect(sema.types.nominalTypeParameterSymbols(for: classSymbol).count == 2)
            #expect(sema.symbols.sourceFileID(for: classSymbol) != nil)

            let constructorSymbol = try #require(
                sema.symbols.lookupAll(fqName: classFQName + [interner.intern("<init>")]).first { symbolID in
                    sema.symbols.symbol(symbolID)?.kind == .constructor
                }
            )
            let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
            let constructorSignature = try #require(sema.symbols.functionSignature(for: constructorSymbol))

            #expect(!constructorInfo.flags.contains(.synthetic))
            #expect(constructorSignature.parameterTypes.count == 2)
            #expect(constructorSignature.classTypeParameterCount == 2)
            #expect(sema.symbols.externalLinkName(for: constructorSymbol) == nil)
        }
    }
}
#endif
