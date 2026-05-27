@testable import CompilerCore
import XCTest

final class NativeCInteropCFunctionSurfaceTests: XCTestCase {
    func testCFunctionClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CFunction surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ name: String) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: ["kotlinx", "cinterop", name].map { interner.intern($0) }),
                "kotlinx.cinterop.\(name) must be registered"
            )
        }

        let cFunctionSymbol = try cinteropSymbol("CFunction")
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: cFunctionSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let cFunctionType = sema.types.make(.classType(ClassType(
            classSymbol: cFunctionSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("NativePtr"),
            args: [],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.symbol(cFunctionSymbol)?.kind, .class)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: cFunctionSymbol), [.invariant])
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [sema.types.anyType])
        XCTAssertEqual(sema.symbols.propertyType(for: cFunctionSymbol), cFunctionType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cFunctionSymbol), [try cinteropSymbol("CPointed")])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cFunctionSymbol), [try cinteropSymbol("CPointed")])

        let fqName = try XCTUnwrap(sema.symbols.symbol(cFunctionSymbol)?.fqName)
        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == cFunctionType
        })
        XCTAssertEqual(constructorSignature.typeParameterSymbols, [typeParameter])
        XCTAssertEqual(constructorSignature.classTypeParameterCount, 1)
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [false])
    }

    func testCFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CFunction

        fun pass(value: CFunction<() -> Int>): CFunction<() -> Int> {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CFunction to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
