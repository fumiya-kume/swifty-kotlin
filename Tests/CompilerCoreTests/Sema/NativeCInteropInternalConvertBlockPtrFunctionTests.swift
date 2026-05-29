@testable import CompilerCore
import XCTest

final class NativeCInteropInternalConvertBlockPtrFunctionTests: XCTestCase {
    func testConvertBlockPtrToKotlinFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected convertBlockPtrToKotlinFunction surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let internalPkg = ["kotlinx", "cinterop", "internal"].map { interner.intern($0) }
        let nativePtrSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("NativePtr")])
        )
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: nativePtrSymbol,
            args: [],
            nullability: .nonNull
        )))
        let function = try XCTUnwrap(
            sema.symbols.lookup(fqName: internalPkg + [interner.intern("convertBlockPtrToKotlinFunction")]),
            "convertBlockPtrToKotlinFunction must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(signature.receiverType, nil)
        XCTAssertEqual(signature.parameterTypes, [nativePtrType])
        XCTAssertEqual(signature.returnType, sema.types.anyType)
    }

    func testConvertBlockPtrToKotlinFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.NativePtr
        import kotlinx.cinterop.internal.convertBlockPtrToKotlinFunction

        fun convert(blockPtr: NativePtr): Any = convertBlockPtrToKotlinFunction(blockPtr)
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected convertBlockPtrToKotlinFunction to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
