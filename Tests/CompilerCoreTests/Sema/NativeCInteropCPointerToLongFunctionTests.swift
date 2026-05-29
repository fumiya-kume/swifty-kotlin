@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerToLongFunctionTests: XCTestCase {
    func testCPointerNullableToLongFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer<T>?.toLong surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toLong")]).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID),
                      signature.parameterTypes.isEmpty,
                      signature.returnType == sema.types.longType,
                      let receiverType = signature.receiverType,
                      case let .classType(receiverClassType) = sema.types.kind(of: receiverType)
                else {
                    return false
                }
                return receiverClassType.nullability == .nullable
                    && !signature.typeParameterSymbols.isEmpty
            },
            "CPointer<T>?.toLong must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(signature.typeParameterUpperBoundsList.count, 1)
    }

    func testCPointerNullableToLongFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toLong

        fun address(pointer: CPointer<ByteVar>?): Long = pointer.toLong()
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer<T>?.toLong to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
