@testable import CompilerCore
import XCTest

final class NativeCInteropByteArrayToKStringRangeFunctionTests: XCTestCase {
    func testByteArrayToKStringRangeFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ByteArray.toKString range surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let byteArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("ByteArray")])
        )
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKString")]).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes == [sema.types.intType, sema.types.intType, sema.types.booleanType]
                    && signature.returnType == sema.types.stringType
            },
            "ByteArray.toKString(startIndex, endIndex, throwOnInvalidSequence) must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(signature.valueParameterHasDefaultValues, [true, true, true])
    }

    func testByteArrayToKStringRangeFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.toKString

        fun convert(values: ByteArray): String = values.toKString(0, 2, true)
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ByteArray.toKString range overload to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
