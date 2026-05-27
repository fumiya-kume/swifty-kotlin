@testable import CompilerCore
import XCTest

final class NativeCInteropShortArrayToCValuesFunctionTests: XCTestCase {
    func testShortArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ShortArray.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let shortArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("ShortArray")]),
            "kotlin.ShortArray must be registered"
        )
        let shortArrayType = sema.types.make(.classType(ClassType(
            classSymbol: shortArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValuesSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let shortVarSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("ShortVar")]),
            "kotlinx.cinterop.ShortVar must be registered"
        )
        let shortVarType = sema.types.make(.classType(ClassType(
            classSymbol: shortVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(shortVarType)],
            nullability: .nonNull
        )))

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)
        let toCValues = try XCTUnwrap(toCValuesCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == shortArrayType
                && signature.parameterTypes.isEmpty
                && signature.returnType == expectedReturnType
        })
        let flags = try XCTUnwrap(sema.symbols.symbol(toCValues)?.flags)

        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: toCValues), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testShortArrayToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.ShortVar
        import kotlinx.cinterop.toCValues

        fun toShorts(shorts: ShortArray): CValues<ShortVar> {
            return shorts.toCValues()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ShortArray.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
