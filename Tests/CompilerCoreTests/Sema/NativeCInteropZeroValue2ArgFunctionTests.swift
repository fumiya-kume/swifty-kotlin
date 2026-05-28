@testable import CompilerCore
import XCTest

/// Tests for STDLIB-CINTEROP-FN-048: `zeroValue<T>(size: Int, align: Int)` in kotlinx.cinterop package.
final class NativeCInteropZeroValue2ArgFunctionTests: XCTestCase {
    func testZeroValue2ArgSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected zeroValue<T>(size, align) surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ name: String) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: cinteropPkg + [interner.intern(name)]),
                "kotlinx.cinterop.\(name) must be registered"
            )
        }

        let cVariableSymbol = try cinteropSymbol("CVariable")
        let cVariableType = sema.types.make(.classType(ClassType(
            classSymbol: cVariableSymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValueSymbol = try cinteropSymbol("CValue")

        let zeroValueFQName = cinteropPkg + [interner.intern("zeroValue")]
        let candidates = sema.symbols.lookupAll(fqName: zeroValueFQName)
        let zeroValue2Arg = try XCTUnwrap(
            candidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.parameterTypes.count == 2
                    && signature.typeParameterSymbols.count == 1
            },
            "kotlinx.cinterop.zeroValue<T>(size: Int, align: Int) must be registered"
        )

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: zeroValue2Arg))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValueSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let flags = try XCTUnwrap(sema.symbols.symbol(zeroValue2Arg)?.flags)
        let typeParameterFlags = try XCTUnwrap(sema.symbols.symbol(typeParameter)?.flags)

        XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        XCTAssertEqual(sema.symbols.parentSymbol(for: zeroValue2Arg), sema.symbols.lookup(fqName: cinteropPkg))
        XCTAssertEqual(signature.parameterTypes, [sema.types.intType, sema.types.intType])
        XCTAssertEqual(signature.returnType, expectedReturnType)
        XCTAssertEqual(signature.reifiedTypeParameterIndices, [0])
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[cVariableType]])
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cVariableType])
        XCTAssertTrue(typeParameterFlags.isSuperset(of: [.synthetic, .reifiedTypeParameter]))
    }

    func testZeroValue2ArgResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValue
        import kotlinx.cinterop.CVariable
        import kotlinx.cinterop.zeroValue

        fun <T : CVariable> makeZeroValue(size: Int, align: Int): CValue<T> {
            return zeroValue<T>(size, align)
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected zeroValue<T>(size, align) to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
