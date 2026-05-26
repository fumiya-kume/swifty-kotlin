@testable import CompilerCore
import XCTest

final class NativeCInteropFloatArrayToCValuesFunctionTests: XCTestCase {
    func testFloatArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected FloatArray.toCValues surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let floatArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("FloatArray")]),
            "kotlin.FloatArray must be registered"
        )
        let floatVarSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("FloatVar")]),
            "kotlinx.cinterop.FloatVar must be registered"
        )
        let cValuesSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: floatArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let floatVarType = sema.types.make(.classType(ClassType(
            classSymbol: floatVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(floatVarType)],
            nullability: .nonNull
        )))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toCValues")]).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == returnType
            },
            "FloatArray.toCValues must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(sema.symbols.symbol(function)?.kind, .function)
        XCTAssertTrue(sema.symbols.symbol(function)?.flags.contains(.synthetic) == true)
        XCTAssertEqual(signature.receiverType, receiverType)
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.returnType, returnType)
        XCTAssertEqual(signature.typeParameterSymbols, [])
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [])
    }

    func testFloatArrayToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.FloatVar
        import kotlinx.cinterop.toCValues

        fun convert(values: FloatArray): CValues<FloatVar> {
            return values.toCValues()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected FloatArray.toCValues to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
