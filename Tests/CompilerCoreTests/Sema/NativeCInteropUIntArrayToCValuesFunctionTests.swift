@testable import CompilerCore
import XCTest

final class NativeCInteropUIntArrayToCValuesFunctionTests: XCTestCase {
    func testUIntArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected UIntArray.toCValues surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let uIntArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("UIntArray")])
        )
        let uIntVarSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("UIntVar")]))
        let cValuesSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: uIntArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let uIntVarType = sema.types.make(.classType(ClassType(
            classSymbol: uIntVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(uIntVarType)],
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
            "UIntArray.toCValues must be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(function)?.kind, .function)
        XCTAssertTrue(sema.symbols.annotations(for: function).contains {
            $0.annotationFQName == "kotlin.ExperimentalUnsignedTypes"
        })
    }

    func testUIntArrayToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.UIntVar
        import kotlinx.cinterop.toCValues

        fun convert(values: UIntArray): CValues<UIntVar> = values.toCValues()
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected UIntArray.toCValues to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
