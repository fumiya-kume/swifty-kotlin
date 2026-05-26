@testable import CompilerCore
import XCTest

final class NativeCInteropUShortArrayToCValuesFunctionTests: XCTestCase {
    func testUShortArrayToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected UShortArray.toCValues surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let uShortArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("UShortArray")]),
            "kotlin.UShortArray must be registered"
        )
        let uShortVarSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("UShortVar")]),
            "kotlinx.cinterop.UShortVar must be registered"
        )
        let cValuesSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValues")]),
            "kotlinx.cinterop.CValues must be registered"
        )
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: uShortArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let uShortVarType = sema.types.make(.classType(ClassType(
            classSymbol: uShortVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(uShortVarType)],
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
            "UShortArray.toCValues must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(sema.symbols.symbol(function)?.kind, .function)
        XCTAssertTrue(sema.symbols.symbol(function)?.flags.contains(.synthetic) == true)
        XCTAssertEqual(signature.receiverType, receiverType)
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.returnType, returnType)
        XCTAssertEqual(signature.typeParameterSymbols, [])
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [])
        XCTAssertTrue(
            sema.symbols.annotations(for: function).contains { $0.annotationFQName == "kotlin.ExperimentalUnsignedTypes" },
            "UShortArray.toCValues must carry @ExperimentalUnsignedTypes metadata"
        )
    }

    func testUShortArrayToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        @file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.UShortVar
        import kotlinx.cinterop.toCValues

        fun convert(values: UShortArray): CValues<UShortVar> {
            return values.toCValues()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected UShortArray.toCValues to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
