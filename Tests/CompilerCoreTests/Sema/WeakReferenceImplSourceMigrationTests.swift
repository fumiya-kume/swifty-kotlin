#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-1258: WeakReferenceImpl.get must remain the bundled Kotlin declaration
/// matching the Kotlin/Native private runtime contract.
@Suite
struct WeakReferenceImplSourceMigrationTests {
    @Test
    func weakReferenceImplGetMatchesKotlinNativeContract() throws {
        let ctx = makeContextFromSource("fun probe() {}")
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected WeakReferenceImpl source declarations to type-check, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let classFQName = ["kotlin", "native", "ref", "WeakReferenceImpl"].map(interner.intern)
        let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
        let classInfo = try #require(sema.symbols.symbol(classSymbol))

        #expect(classInfo.kind == .class)
        #expect(classInfo.visibility == .internal)
        #expect(classInfo.flags.contains(.abstractType))
        #expect(!classInfo.flags.contains(.synthetic))

        let getFQName = classFQName + [interner.intern("get")]
        let getSymbols = sema.symbols.lookupAll(fqName: getFQName)
        #expect(getSymbols.count == 1, "WeakReferenceImpl.get must have one source declaration")

        let getSymbol = try #require(getSymbols.first)
        let getInfo = try #require(sema.symbols.symbol(getSymbol))
        let signature = try #require(sema.symbols.functionSignature(for: getSymbol))

        #expect(getInfo.kind == .function)
        #expect(getInfo.visibility == .public)
        #expect(getInfo.flags.contains(.abstractType))
        #expect(!getInfo.flags.contains(.synthetic))
        #expect(getInfo.declSite != nil)
        #expect(sema.symbols.isSourceBackedSymbol(getSymbol))
        #expect(sema.symbols.externalLinkName(for: getSymbol) == nil)
        #expect(signature.parameterTypes.isEmpty)
        #expect(signature.returnType == sema.types.nullableAnyType)

        let receiverType = try #require(signature.receiverType)
        guard case let .classType(receiverClass) = sema.types.kind(of: receiverType) else {
            Issue.record("WeakReferenceImpl.get must have a WeakReferenceImpl receiver")
            return
        }
        #expect(receiverClass.classSymbol == classSymbol)

        let sourceFileID = try #require(sema.symbols.sourceFileID(for: getSymbol))
        #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/native/ref/Stdlib.kt")
    }
}
#endif
