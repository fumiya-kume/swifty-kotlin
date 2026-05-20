@testable import CompilerCore
import XCTest

final class ReflectKProperty0SyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected KProperty0 surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKProperty0SurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let functionPackage = ["kotlin", "Function"].map { interner.intern($0) }

        let kPropertySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty")]
        ))
        let kProperty0Symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty0")]
        ))
        let function0Symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: functionPackage + [interner.intern("Function0")]
        ))

        let kProperty0Info = try XCTUnwrap(sema.symbols.symbol(kProperty0Symbol))
        XCTAssertEqual(kProperty0Info.kind, .interface)
        XCTAssertTrue(kProperty0Info.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kProperty0Symbol)
        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: kProperty0Symbol), [.out])

        let valueType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: kProperty0Symbol,
            args: [.out(valueType)],
            nullability: .nonNull
        )))

        XCTAssertTrue(sema.symbols.directSupertypes(for: kProperty0Symbol).contains(kPropertySymbol))
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kProperty0Symbol, supertype: kPropertySymbol),
            [.out(valueType)]
        )
        XCTAssertTrue(sema.symbols.directSupertypes(for: kProperty0Symbol).contains(function0Symbol))
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kProperty0Symbol, supertype: function0Symbol),
            [.out(valueType)]
        )

        let getSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty0"), interner.intern("get")]
        ))
        let getSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getSymbol))
        XCTAssertEqual(getSignature.receiverType, receiverType)
        XCTAssertEqual(getSignature.parameterTypes, [])
        XCTAssertEqual(getSignature.returnType, valueType)
        XCTAssertEqual(getSignature.typeParameterSymbols, typeParams)
        XCTAssertEqual(getSignature.classTypeParameterCount, 1)

        let getDelegateSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty0"), interner.intern("getDelegate")]
        ))
        let getDelegateSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getDelegateSymbol))
        XCTAssertEqual(getDelegateSignature.receiverType, receiverType)
        XCTAssertEqual(getDelegateSignature.parameterTypes, [])
        XCTAssertEqual(getDelegateSignature.returnType, sema.types.nullableAnyType)
        XCTAssertEqual(getDelegateSignature.typeParameterSymbols, typeParams)
        XCTAssertEqual(getDelegateSignature.classTypeParameterCount, 1)

        let invokeSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty0"), interner.intern("invoke")]
        ))
        let invokeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: invokeSymbol))
        XCTAssertEqual(invokeSignature.receiverType, receiverType)
        XCTAssertEqual(invokeSignature.parameterTypes, [])
        XCTAssertEqual(invokeSignature.returnType, valueType)
        XCTAssertTrue(sema.symbols.symbol(invokeSymbol)?.flags.contains(.operatorFunction) == true)
        XCTAssertEqual(invokeSignature.typeParameterSymbols, typeParams)
        XCTAssertEqual(invokeSignature.classTypeParameterCount, 1)
    }

    func testKProperty0MemberCallsResolveInSource() throws {
        let source = """
        import kotlin.reflect.KProperty0

        fun <V> read(property: KProperty0<V>): V {
            val first = property.get()
            val second = property.invoke()
            return first
        }

        fun <V> delegateOf(property: KProperty0<V>): Any? =
            property.getDelegate()
        """

        _ = try makeSema(source: source)
    }
}
