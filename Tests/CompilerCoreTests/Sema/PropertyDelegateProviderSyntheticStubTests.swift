@testable import CompilerCore
import XCTest

final class PropertyDelegateProviderSyntheticStubTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testPropertyDelegateProviderSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let propertiesFQName = ["kotlin", "properties"].map { interner.intern($0) }
        let providerFQName = propertiesFQName + [interner.intern("PropertyDelegateProvider")]
        let kPropertyFQName = ["kotlin", "reflect", "KProperty"].map { interner.intern($0) }

        let providerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: providerFQName))
        let providerInfo = try XCTUnwrap(sema.symbols.symbol(providerSymbol))
        XCTAssertEqual(providerInfo.kind, .interface)
        XCTAssertTrue(providerInfo.flags.contains(.funInterface))
        XCTAssertTrue(providerInfo.flags.contains(.synthetic))

        let typeParameters = sema.types.nominalTypeParameterSymbols(for: providerSymbol)
        XCTAssertEqual(try resolvedNames(typeParameters, sema: sema, interner: interner), ["T", "D"])
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: providerSymbol), [.in, .out])

        let thisRefType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameters[0],
            nullability: .nonNull
        )))
        let delegateType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameters[1],
            nullability: .nonNull
        )))
        let providerType = sema.types.make(.classType(ClassType(
            classSymbol: providerSymbol,
            args: [.invariant(thisRefType), .invariant(delegateType)],
            nullability: .nonNull
        )))
        let kPropertySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kPropertyFQName))
        let kPropertyType = sema.types.make(.classType(ClassType(
            classSymbol: kPropertySymbol,
            args: [.star],
            nullability: .nonNull
        )))

        let provideSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: providerFQName + [interner.intern("provideDelegate")]))
        let provideInfo = try XCTUnwrap(sema.symbols.symbol(provideSymbol))
        XCTAssertEqual(provideInfo.kind, .function)
        XCTAssertTrue(provideInfo.flags.isSuperset(of: [.abstractType, .operatorFunction, .synthetic]))

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: provideSymbol))
        XCTAssertEqual(signature.receiverType, providerType)
        XCTAssertEqual(signature.parameterTypes, [thisRefType, kPropertyType])
        XCTAssertEqual(signature.returnType, delegateType)
        XCTAssertEqual(signature.typeParameterSymbols, typeParameters)
        XCTAssertEqual(signature.classTypeParameterCount, 2)
    }

    func testProviderReturnTypeFeedsDelegatedPropertyInference() throws {
        let source = """
        package sample

        import kotlin.properties.PropertyDelegateProvider
        import kotlin.reflect.KProperty

        class ResourceDelegate {
            operator fun getValue(thisRef: Any?, property: KProperty<*>): String = "value"
        }

        fun provider(): PropertyDelegateProvider<Any?, ResourceDelegate> =
            PropertyDelegateProvider<Any?, ResourceDelegate> { thisRef, property -> ResourceDelegate() }

        val resource by provider()
        """
        let (sema, interner) = try makeSema(source: source)
        let sampleFQName = [interner.intern("sample")]
        let resourceSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: sampleFQName + [interner.intern("resource")]))
        XCTAssertEqual(sema.symbols.propertyType(for: resourceSymbol), sema.types.stringType)
        XCTAssertTrue(sema.symbols.hasProvideDelegate(for: resourceSymbol))

        let provideSymbol = try XCTUnwrap(sema.symbols.delegateProvideDelegateSymbol(for: resourceSymbol))
        let provideInfo = try XCTUnwrap(sema.symbols.symbol(provideSymbol))
        XCTAssertEqual(interner.resolve(provideInfo.name), "provideDelegate")
        XCTAssertTrue(provideInfo.flags.contains(.operatorFunction))

        let getValueSymbol = try XCTUnwrap(sema.symbols.delegateGetValueSymbol(for: resourceSymbol))
        let getValueInfo = try XCTUnwrap(sema.symbols.symbol(getValueSymbol))
        XCTAssertEqual(interner.resolve(getValueInfo.name), "getValue")
    }

    private func resolvedNames(
        _ symbols: [SymbolID],
        sema: SemaModule,
        interner: StringInterner
    ) throws -> [String] {
        try symbols.map { symbol in
            try interner.resolve(XCTUnwrap(sema.symbols.symbol(symbol)?.name))
        }
    }
}
