@testable import CompilerCore
import XCTest

final class NativeCInteropFloatArrayToCValuesFunctionTests: XCTestCase {
    func testFloatArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected FloatArray.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let floatArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("FloatArray")]),
            "kotlin.FloatArray must be registered"
        )
        let floatArrayType = sema.types.make(.classType(ClassType(
            classSymbol: floatArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValuesSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let floatVarSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("FloatVar")]),
            "kotlinx.cinterop.FloatVar must be registered"
        )
        let floatVarType = sema.types.make(.classType(ClassType(
            classSymbol: floatVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(floatVarType)],
            nullability: .nonNull
        )))

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)
        let toCValues = try XCTUnwrap(toCValuesCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == floatArrayType
                && signature.parameterTypes.isEmpty
                && signature.returnType == expectedReturnType
        })
        let flags = try XCTUnwrap(sema.symbols.symbol(toCValues)?.flags)

        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: toCValues), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testFloatArrayToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.FloatVar
        import kotlinx.cinterop.toCValues

        fun toFloats(floats: FloatArray): CValues<FloatVar> {
            return floats.toCValues()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected FloatArray.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
