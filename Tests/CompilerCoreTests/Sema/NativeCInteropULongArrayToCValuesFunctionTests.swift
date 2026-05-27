@testable import CompilerCore
import XCTest

final class NativeCInteropULongArrayToCValuesFunctionTests: XCTestCase {
    func testULongArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ULongArray.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let uLongArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("ULongArray")]),
            "kotlin.ULongArray must be registered"
        )
        let uLongArrayType = sema.types.make(.classType(ClassType(
            classSymbol: uLongArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValuesSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let uLongVarSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("ULongVar")]),
            "kotlinx.cinterop.ULongVar must be registered"
        )
        let uLongVarType = sema.types.make(.classType(ClassType(
            classSymbol: uLongVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(uLongVarType)],
            nullability: .nonNull
        )))

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)
        let toCValues = try XCTUnwrap(toCValuesCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == uLongArrayType
                && signature.parameterTypes.isEmpty
                && signature.returnType == expectedReturnType
        })
        let flags = try XCTUnwrap(sema.symbols.symbol(toCValues)?.flags)

        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: toCValues), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testULongArrayToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.ULongVar
        import kotlinx.cinterop.toCValues

        fun toULongs(ulongs: ULongArray): CValues<ULongVar> {
            return ulongs.toCValues()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ULongArray.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
