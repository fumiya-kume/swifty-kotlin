#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct AtomicNativePtrConstructorSourceTests {
    @Test
    func constructorMatchesKotlin2310NativeContract() throws {
        let ctx = makeContextFromSource("""
        @file:Suppress("DEPRECATION_ERROR")

        import kotlinx.cinterop.NativePtr
        import kotlin.native.concurrent.AtomicNativePtr

        fun construct(value: NativePtr): AtomicNativePtr = AtomicNativePtr(value)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let atomicFQName = ["kotlin", "native", "concurrent", "AtomicNativePtr"].map(interner.intern)
        let atomicSymbol = try #require(sema.symbols.lookup(fqName: atomicFQName))
        let atomicInfo = try #require(sema.symbols.symbol(atomicSymbol))
        #expect(atomicInfo.kind == .class)
        #expect(atomicInfo.visibility == .public)
        #expect(!atomicInfo.flags.contains(.synthetic))
        #expect(atomicInfo.declSite != nil)
        #expect(sema.symbols.sourceFileID(for: atomicSymbol) != nil)
        #expect(
            sema.symbols.annotations(for: atomicSymbol).contains {
                $0.annotationFQName == "Deprecated" || $0.annotationFQName == "kotlin.Deprecated"
            }
        )

        let nativePtrFQName = ["kotlinx", "cinterop", "NativePtr"].map(interner.intern)
        let nativePtrSymbol = try #require(sema.symbols.lookup(fqName: nativePtrFQName))
        let nativePtrType = try #require(sema.symbols.propertyType(for: nativePtrSymbol))
        let atomicType = sema.types.make(.classType(ClassType(
            classSymbol: atomicSymbol,
            args: [],
            nullability: .nonNull
        )))
        let constructor = try #require(
            sema.symbols.lookupAll(fqName: atomicFQName + [interner.intern("<init>")]).first {
                guard let signature = sema.symbols.functionSignature(for: $0) else {
                    return false
                }
                return signature.parameterTypes == [nativePtrType]
                    && signature.returnType == atomicType
            }
        )
        let constructorInfo = try #require(sema.symbols.symbol(constructor))
        #expect(constructorInfo.kind == .constructor)
        #expect(constructorInfo.visibility == .public)
        #expect(!constructorInfo.flags.contains(.synthetic))
        #expect(constructorInfo.declSite != nil)
        #expect(sema.symbols.externalLinkName(for: constructor) == nil)
    }
}
#endif
