#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct FreezableAtomicReferenceSourceTests {
    @Test
    func constructorIsSourceBackedAndUsesNativeCreateBridge() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let classFQName = ["kotlin", "native", "concurrent", "FreezableAtomicReference"].map(interner.intern)
        let classSymbol = try #require(sema.symbols.lookup(fqName: classFQName))
        let classInfo = try #require(sema.symbols.symbol(classSymbol))
        #expect(classInfo.kind == .class)
        #expect(classInfo.visibility == .public)
        #expect(!classInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(classSymbol))

        let typeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: classSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let classType = sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        let constructorFQName = classFQName + [interner.intern("<init>")]
        let constructor = try #require(
            sema.symbols.lookupAll(fqName: constructorFQName).first { symbol in
                guard sema.symbols.symbol(symbol)?.kind == .constructor,
                      let signature = sema.symbols.functionSignature(for: symbol)
                else {
                    return false
                }
                return signature.parameterTypes == [typeParameterType]
                    && signature.returnType == classType
            }
        )
        let constructorInfo = try #require(sema.symbols.symbol(constructor))
        #expect(constructorInfo.visibility == .public)
        #expect(!constructorInfo.flags.contains(.synthetic))
        #expect(sema.symbols.isSourceBackedSymbol(constructor))
        #expect(sema.symbols.externalLinkName(for: constructor) == "kk_freezable_atomic_ref_create")
    }
}
#endif
