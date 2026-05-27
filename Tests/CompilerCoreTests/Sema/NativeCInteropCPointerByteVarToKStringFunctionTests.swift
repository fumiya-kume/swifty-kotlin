@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerByteVarToKStringFunctionTests: XCTestCase {
    func testCPointerByteVarToKStringFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer<ByteVar>.toKString() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let cPointerSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]),
            "kotlinx.cinterop.CPointer must be registered"
        )
        let byteVarOfSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("ByteVarOf")]),
            "kotlinx.cinterop.ByteVarOf must be registered"
        )
        let byteVarType = sema.types.make(.classType(ClassType(
            classSymbol: byteVarOfSymbol,
            args: [.invariant(sema.types.intType)],
            nullability: .nonNull
        )))
        let expectedReceiverType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(byteVarType)],
            nullability: .nonNull
        )))

        let toKStringFQName = cinteropPkg + [interner.intern("toKString")]
        let candidates = sema.symbols.lookupAll(fqName: toKStringFQName)
        let toKString = try XCTUnwrap(candidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == expectedReceiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.stringType
        })
        let flags = try XCTUnwrap(sema.symbols.symbol(toKString)?.flags)
        XCTAssertTrue(flags.contains(.synthetic))
    }

    func testCPointerByteVarToKStringFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toKString

        fun decode(p: CPointer<ByteVar>): String {
            return p.toKString()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer<ByteVar>.toKString() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
