@testable import CompilerCore
import XCTest

final class NativeCInteropDoubleArrayToCValuesFunctionTests: XCTestCase {
    func testDoubleArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected DoubleArray.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let doubleArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("DoubleArray")]),
            "kotlin.DoubleArray must be registered"
        )
        let doubleArrayType = sema.types.make(.classType(ClassType(
            classSymbol: doubleArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValuesSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let doubleVarSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("DoubleVar")]),
            "kotlinx.cinterop.DoubleVar must be registered"
        )
        let doubleVarType = sema.types.make(.classType(ClassType(
            classSymbol: doubleVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(doubleVarType)],
            nullability: .nonNull
        )))

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)
        let toCValues = try XCTUnwrap(toCValuesCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == doubleArrayType
                && signature.parameterTypes.isEmpty
                && signature.returnType == expectedReturnType
        })
        let flags = try XCTUnwrap(sema.symbols.symbol(toCValues)?.flags)

        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: toCValues), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testDoubleArrayToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.DoubleVar
        import kotlinx.cinterop.toCValues

        fun toDoubles(doubles: DoubleArray): CValues<DoubleVar> {
            return doubles.toCValues()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected DoubleArray.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
