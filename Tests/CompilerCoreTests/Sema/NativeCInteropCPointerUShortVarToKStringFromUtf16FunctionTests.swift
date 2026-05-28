@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerUShortVarToKStringFromUtf16FunctionTests: XCTestCase {
    func testCPointerUShortVarToKStringFromUtf16FunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer<UShortVar>.toKStringFromUtf16 surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let cPointerSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]),
            "kotlinx.cinterop.CPointer must be registered"
        )
        let uShortVarSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("UShortVar")]),
            "kotlinx.cinterop.UShortVar must be registered"
        )
        let uShortVarType = sema.types.make(.classType(ClassType(
            classSymbol: uShortVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(uShortVarType)],
            nullability: .nonNull
        )))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(
                fqName: cinteropPkg + [interner.intern("toKStringFromUtf16")]
            ).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == sema.types.stringType
            },
            "CPointer<UShortVar>.toKStringFromUtf16 must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(sema.symbols.symbol(function)?.kind, .function)
        XCTAssertTrue(sema.symbols.symbol(function)?.flags.contains(.synthetic) == true)
        XCTAssertEqual(signature.receiverType, receiverType)
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.returnType, sema.types.stringType)
        XCTAssertEqual(signature.typeParameterSymbols, [])
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [])
    }

    func testCPointerUShortVarToKStringFromUtf16FunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.UShortVar
        import kotlinx.cinterop.toKStringFromUtf16

        fun decode(pointer: CPointer<UShortVar>): String {
            return pointer.toKStringFromUtf16()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer<UShortVar>.toKStringFromUtf16 to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
