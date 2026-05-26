@testable import CompilerCore
import XCTest

final class NativeCInteropCValueSurfaceTests: XCTestCase {
    func testCValueClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CValue surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: (["kotlinx", "cinterop"] + path).map { interner.intern($0) }),
                "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered"
            )
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }
        func cinteropType(_ path: String...) throws -> TypeID {
            sema.types.make(.classType(ClassType(
                classSymbol: try cinteropSymbol(path),
                args: [],
                nullability: .nonNull
            )))
        }

        let cValueSymbol = try cinteropSymbol("CValue")
        let cValuesSymbol = try cinteropSymbol("CValues")
        let cVariableType = try cinteropType("CVariable")
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: cValueSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let cValueType = sema.types.make(.classType(ClassType(
            classSymbol: cValueSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let fqName = try XCTUnwrap(sema.symbols.symbol(cValueSymbol)?.fqName)
        let flags = try XCTUnwrap(sema.symbols.symbol(cValueSymbol)?.flags)

        XCTAssertEqual(sema.symbols.symbol(cValueSymbol)?.kind, .class)
        XCTAssertTrue(flags.contains(.abstractType))
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: cValueSymbol), [.invariant])
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cVariableType])
        XCTAssertEqual(sema.symbols.propertyType(for: cValueSymbol), cValueType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cValueSymbol), [cValuesSymbol])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cValueSymbol), [cValuesSymbol])
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: cValueSymbol, supertype: cValuesSymbol),
            [.invariant(typeParameterType)]
        )
        XCTAssertEqual(
            sema.types.nominalSupertypeTypeArgs(for: cValueSymbol, supertype: cValuesSymbol),
            [.invariant(typeParameterType)]
        )

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes.isEmpty && $0.returnType == cValueType
        })
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [])
    }

    func testCValueResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValue
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.CVariable

        fun <T : CVariable> upcast(value: CValue<T>): CValues<T> {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CValue to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
