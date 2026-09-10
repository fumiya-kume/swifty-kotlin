#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct NativeAtomicReferenceConstructorTests {
    @Test
    func constructorIsSourceBackedWithGenericValueParameter() throws {
        let source = """
        @file:Suppress("DEPRECATION_ERROR")

        import kotlin.native.concurrent.AtomicReference

        fun construct(value: String): AtomicReference<String> = AtomicReference(value)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected AtomicReference constructor to type-check, got: \(errors.map { $0.code + ": " + $0.message })"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let ownerFQName = ["kotlin", "native", "concurrent", "AtomicReference"].map(interner.intern)
        let owner = try #require(sema.symbols.lookup(fqName: ownerFQName))
        let ownerInfo = try #require(sema.symbols.symbol(owner))
        #expect(ownerInfo.kind == .class)
        #expect(!ownerInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(owner))

        let constructor = try #require(
            sema.symbols.lookupAll(fqName: ownerFQName + [interner.intern("<init>")])
                .first { sema.symbols.symbol($0)?.kind == .constructor }
        )
        let constructorInfo = try #require(sema.symbols.symbol(constructor))
        let signature = try #require(sema.symbols.functionSignature(for: constructor))
        #expect(constructorInfo.visibility == .public)
        #expect(!constructorInfo.flags.contains(.synthetic))
        #expect(sema.symbols.externalLinkName(for: constructor) == nil)
        #expect(sema.symbols.isSourceBackedSymbol(constructor))
        #expect(signature.parameterTypes.count == 1)
        #expect(signature.returnType == sema.types.make(.classType(ClassType(
            classSymbol: owner,
            args: [.invariant(signature.parameterTypes[0])],
            nullability: .nonNull
        ))))
        let sourceFile = try #require(sema.symbols.sourceFileID(for: owner))
        #expect(constructorInfo.declSite?.start.file == sourceFile)
        #expect(ctx.sourceManager.path(of: sourceFile) == "__bundled_kotlin/native/concurrent/AtomicReference/Stdlib.kt")
    }
}
#endif
