@testable import CompilerCore
import XCTest

final class ReflectKMutableProperty0SyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected KMutableProperty0 surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKMutableProperty0SurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let functionPackage = ["kotlin", "Function"].map { interner.intern($0) }

        let kProperty0Symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty0")]
        ))
        let kMutablePropertySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty")]
        ))
        let kMutableProperty0Symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty0")]
        ))
        let function0Symbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: functionPackage + [interner.intern("Function0")]
        ))

        let kMutableProperty0Info = try XCTUnwrap(sema.symbols.symbol(kMutableProperty0Symbol))
        XCTAssertEqual(kMutableProperty0Info.kind, .interface)
        XCTAssertTrue(kMutableProperty0Info.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kMutableProperty0Symbol)
        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: kMutableProperty0Symbol), [.invariant])

        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        let supertypes = sema.symbols.directSupertypes(for: kMutableProperty0Symbol)
        XCTAssertTrue(supertypes.contains(kProperty0Symbol))
        XCTAssertTrue(supertypes.contains(kMutablePropertySymbol))
        XCTAssertTrue(supertypes.contains(function0Symbol))
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty0Symbol, supertype: kProperty0Symbol),
            [.invariant(valueType)]
        )
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty0Symbol, supertype: kMutablePropertySymbol),
            [.invariant(valueType)]
        )
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty0Symbol, supertype: function0Symbol),
            [.out(valueType)]
        )

        let setSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty0"), interner.intern("set")]
        ))
        let setSignature = try XCTUnwrap(sema.symbols.functionSignature(for: setSymbol))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: kMutableProperty0Symbol,
            args: [.invariant(valueType)],
            nullability: .nonNull
        )))
        XCTAssertEqual(setSignature.receiverType, receiverType)
        XCTAssertEqual(setSignature.parameterTypes, [valueType])
        XCTAssertEqual(setSignature.returnType, sema.types.unitType)
        XCTAssertEqual(setSignature.typeParameterSymbols, typeParams)
        XCTAssertEqual(setSignature.classTypeParameterCount, 1)
    }

    func testKMutableProperty0SetResolvesInSource() throws {
        let source = """
        import kotlin.reflect.KMutableProperty0

        fun <V> write(property: KMutableProperty0<V>, value: V) {
            property.set(value)
        }
        """

        _ = try makeSema(source: source)
    }
}
