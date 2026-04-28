@testable import CompilerCore
import XCTest

final class ReflectKProperty2SyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected KProperty2 surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKProperty2SurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let functionPackage = ["kotlin", "Function"].map { interner.intern($0) }

        let kPropertySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty")]
        ))
        let kProperty2Symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty2")]
        ))
        let function2Symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: functionPackage + [interner.intern("Function2")]
        ))

        let kProperty2Info = try XCTUnwrap(sema.symbols.symbol(kProperty2Symbol))
        XCTAssertEqual(kProperty2Info.kind, .interface)
        XCTAssertTrue(kProperty2Info.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kProperty2Symbol)
        XCTAssertEqual(typeParams.count, 3)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: kProperty2Symbol), [.invariant, .invariant, .out])

        let dType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
        let eType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[1], nullability: .nonNull)))
        let vType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[2], nullability: .nonNull)))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: kProperty2Symbol,
            args: [.invariant(dType), .invariant(eType), .out(vType)],
            nullability: .nonNull
        )))

        XCTAssertTrue(sema.symbols.directSupertypes(for: kProperty2Symbol).contains(kPropertySymbol))
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kProperty2Symbol, supertype: kPropertySymbol),
            [.out(vType)]
        )
        XCTAssertTrue(sema.symbols.directSupertypes(for: kProperty2Symbol).contains(function2Symbol))
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kProperty2Symbol, supertype: function2Symbol),
            [.out(vType), .in(dType), .in(eType)]
        )

        let getSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty2"), interner.intern("get")]
        ))
        let getSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getSymbol))
        XCTAssertEqual(getSignature.receiverType, receiverType)
        XCTAssertEqual(getSignature.parameterTypes, [dType, eType])
        XCTAssertEqual(getSignature.returnType, vType)
        XCTAssertEqual(getSignature.typeParameterSymbols, typeParams)
        XCTAssertEqual(getSignature.classTypeParameterCount, 3)

        let getDelegateSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty2"), interner.intern("getDelegate")]
        ))
        let getDelegateSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getDelegateSymbol))
        XCTAssertEqual(getDelegateSignature.receiverType, receiverType)
        XCTAssertEqual(getDelegateSignature.parameterTypes, [dType, eType])
        XCTAssertEqual(getDelegateSignature.returnType, sema.types.nullableAnyType)
        XCTAssertEqual(getDelegateSignature.typeParameterSymbols, typeParams)
        XCTAssertEqual(getDelegateSignature.classTypeParameterCount, 3)

        let invokeSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty2"), interner.intern("invoke")]
        ))
        let invokeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: invokeSymbol))
        XCTAssertEqual(invokeSignature.receiverType, receiverType)
        XCTAssertEqual(invokeSignature.parameterTypes, [dType, eType])
        XCTAssertEqual(invokeSignature.returnType, vType)
        XCTAssertTrue(sema.symbols.symbol(invokeSymbol)?.flags.contains(.operatorFunction) == true)
        XCTAssertEqual(invokeSignature.typeParameterSymbols, typeParams)
        XCTAssertEqual(invokeSignature.classTypeParameterCount, 3)
    }

    func testKProperty2MemberCallsResolveInSource() throws {
        let source = """
        import kotlin.reflect.KProperty2

        fun <D, E, V> read(property: KProperty2<D, E, V>, receiver1: D, receiver2: E): V {
            val first = property.get(receiver1, receiver2)
            val second = property.invoke(receiver1, receiver2)
            return first
        }

        fun <D, E, V> delegateOf(property: KProperty2<D, E, V>, receiver1: D, receiver2: E): Any? =
            property.getDelegate(receiver1, receiver2)
        """

        _ = try makeSema(source: source)
    }
}
