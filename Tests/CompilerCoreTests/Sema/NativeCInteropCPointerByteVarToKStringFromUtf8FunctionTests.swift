@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerByteVarToKStringFromUtf8FunctionTests: XCTestCase {
    func testCPointerByteVarToKStringFromUtf8FunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer<ByteVar>.toKStringFromUtf8 surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let cPointerSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]),
            "kotlinx.cinterop.CPointer must be registered"
        )
        let byteVarSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("ByteVar")]),
            "kotlinx.cinterop.ByteVar must be registered"
        )
        let byteVarType = sema.types.make(.classType(ClassType(
            classSymbol: byteVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(byteVarType)],
            nullability: .nonNull
        )))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(
                fqName: cinteropPkg + [interner.intern("toKStringFromUtf8")]
            ).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == sema.types.stringType
            },
            "CPointer<ByteVar>.toKStringFromUtf8 must be registered"
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

    func testCPointerByteVarToKStringFromUtf8FunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toKStringFromUtf8

        fun decode(pointer: CPointer<ByteVar>): String {
            return pointer.toKStringFromUtf8()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer<ByteVar>.toKStringFromUtf8 to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
