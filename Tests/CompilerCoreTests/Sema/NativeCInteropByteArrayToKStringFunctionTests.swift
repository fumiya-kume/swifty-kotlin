@testable import CompilerCore
import XCTest

final class NativeCInteropByteArrayToKStringFunctionTests: XCTestCase {
    func testByteArrayToKStringFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "compile clean: \(ctx.diagnostics.diagnostics)")
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let kotlinPkg = [interner.intern("kotlin")]

        let byteArraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("ByteArray")]),
            "kotlin.ByteArray must be registered"
        )
        let byteArrayType = sema.types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))

        let candidates = sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKString")])
        let fn = try XCTUnwrap(candidates.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == byteArrayType
                && sig.parameterTypes == [sema.types.intType, sema.types.intType, sema.types.booleanType]
                && sig.returnType == sema.types.stringType
        }, "ByteArray.toKString(startIndex, endIndex, throwOnInvalidSequence) must be registered")
        XCTAssertTrue(try XCTUnwrap(sema.symbols.symbol(fn)?.flags).contains(.synthetic))

        // Verify all three parameters have default values
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: fn))
        XCTAssertEqual(sig.valueParameterHasDefaultValues, [true, true, true])
    }

    func testByteArrayToKStringFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.toKString

        fun decode(bytes: ByteArray): String {
            return bytes.toKString()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve with no args: \(ctx.diagnostics.diagnostics)")
    }

    func testByteArrayToKStringFunctionResolvesWithAllArgs() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.toKString

        fun decode(bytes: ByteArray): String {
            return bytes.toKString(0, bytes.size, false)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve with all args: \(ctx.diagnostics.diagnostics)")
    }
}
