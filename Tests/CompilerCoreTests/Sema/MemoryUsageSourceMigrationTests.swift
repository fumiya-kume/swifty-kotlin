#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1266: The MemoryUsage nominal declaration and Long constructor are
/// backed by bundled Kotlin source. The property remains synthetic for
/// KSP-1267 and is intentionally not covered by this migration.
@Suite
struct MemoryUsageSourceMigrationTests {
    @Test
    func memoryUsageConstructorIsBundledSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected bundled MemoryUsage source to type-check, got: \(errors.map { $0.code + ": " + $0.message })"
            )

            let sema = try #require(ctx.sema)
            let memoryUsageFQName = ["kotlin", "native", "runtime", "MemoryUsage"].map(ctx.interner.intern)
            let classSymbol = try #require(sema.symbols.lookup(fqName: memoryUsageFQName))
            let classInfo = try #require(sema.symbols.symbol(classSymbol))
            #expect(classInfo.kind == .class)
            #expect(!classInfo.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(classSymbol))
            let classFileID = try #require(sema.symbols.sourceFileID(for: classSymbol))
            #expect(ctx.sourceManager.path(of: classFileID) == "__bundled_kotlin/native/runtime/MemoryUsage/Stdlib.kt")

            let constructors = sema.symbols.lookupAll(
                fqName: memoryUsageFQName + [ctx.interner.intern("<init>")]
            ).filter { sema.symbols.symbol($0)?.kind == .constructor }
            #expect(constructors.count == 1, "Expected one source-backed MemoryUsage constructor")
            let constructor = try #require(constructors.first)
            let constructorInfo = try #require(sema.symbols.symbol(constructor))
            let signature = try #require(sema.symbols.functionSignature(for: constructor))
            #expect(!constructorInfo.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(constructor))
            #expect(sema.symbols.externalLinkName(for: constructor) == nil)
            #expect(signature.parameterTypes == [sema.types.longType])
            #expect(signature.returnType == sema.types.make(.classType(ClassType(
                classSymbol: classSymbol,
                args: [],
                nullability: .nonNull
            ))))

            let propertySymbol = try #require(
                sema.symbols.lookup(fqName: memoryUsageFQName + [ctx.interner.intern("totalObjectsSizeBytes")])
            )
            let propertyInfo = try #require(sema.symbols.symbol(propertySymbol))
            #expect(propertyInfo.flags.contains(.synthetic))
            #expect(!sema.symbols.isSourceBackedSymbol(propertySymbol))
            #expect(sema.symbols.propertyType(for: propertySymbol) == sema.types.longType)
        }
    }
}
#endif
