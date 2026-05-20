@testable import CompilerCore
import XCTest

final class ReflectKProperty1SyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected KProperty1 surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKProperty1SurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let functionPackage = ["kotlin", "Function"].map { interner.intern($0) }

        let kPropertySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty")]
        ))
        let kProperty1Symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty1")]
        ))
        let function1Symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: functionPackage + [interner.intern("Function1")]
        ))

        let kProperty1Info = try XCTUnwrap(sema.symbols.symbol(kProperty1Symbol))
        XCTAssertEqual(kProperty1Info.kind, .interface)
        XCTAssertTrue(kProperty1Info.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kProperty1Symbol)
        XCTAssertEqual(typeParams.count, 2)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: kProperty1Symbol), [.invariant, .out])

        let receiverParamType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
        let valueType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[1], nullability: .nonNull)))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: kProperty1Symbol,
            args: [.invariant(receiverParamType), .out(valueType)],
            nullability: .nonNull
        )))

        XCTAssertTrue(sema.symbols.directSupertypes(for: kProperty1Symbol).contains(kPropertySymbol))
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kProperty1Symbol, supertype: kPropertySymbol),
            [.out(valueType)]
        )
        XCTAssertTrue(sema.symbols.directSupertypes(for: kProperty1Symbol).contains(function1Symbol))
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kProperty1Symbol, supertype: function1Symbol),
            [.out(valueType), .in(receiverParamType)]
        )

        let getSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty1"), interner.intern("get")]
        ))
        let getSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getSymbol))
        XCTAssertEqual(getSignature.receiverType, receiverType)
        XCTAssertEqual(getSignature.parameterTypes, [receiverParamType])
        XCTAssertEqual(getSignature.returnType, valueType)
        XCTAssertEqual(getSignature.typeParameterSymbols, typeParams)
        XCTAssertEqual(getSignature.classTypeParameterCount, 2)

        let getDelegateSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty1"), interner.intern("getDelegate")]
        ))
        let getDelegateSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getDelegateSymbol))
        XCTAssertEqual(getDelegateSignature.receiverType, receiverType)
        XCTAssertEqual(getDelegateSignature.parameterTypes, [receiverParamType])
        XCTAssertEqual(getDelegateSignature.returnType, sema.types.nullableAnyType)
        XCTAssertEqual(getDelegateSignature.typeParameterSymbols, typeParams)
        XCTAssertEqual(getDelegateSignature.classTypeParameterCount, 2)

        let invokeSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty1"), interner.intern("invoke")]
        ))
        let invokeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: invokeSymbol))
        XCTAssertEqual(invokeSignature.receiverType, receiverType)
        XCTAssertEqual(invokeSignature.parameterTypes, [receiverParamType])
        XCTAssertEqual(invokeSignature.returnType, valueType)
        XCTAssertTrue(sema.symbols.symbol(invokeSymbol)?.flags.contains(.operatorFunction) == true)
        XCTAssertEqual(invokeSignature.typeParameterSymbols, typeParams)
        XCTAssertEqual(invokeSignature.classTypeParameterCount, 2)
    }

    func testKProperty1MemberCallsResolveInSource() throws {
        let source = """
        import kotlin.reflect.KProperty1

        fun <T, V> read(property: KProperty1<T, V>, receiver: T): V {
            val first = property.get(receiver)
            val second = property.invoke(receiver)
            return first
        }

        fun <T, V> delegateOf(property: KProperty1<T, V>, receiver: T): Any? =
            property.getDelegate(receiver)
        """

        _ = try makeSema(source: source)
    }
}
