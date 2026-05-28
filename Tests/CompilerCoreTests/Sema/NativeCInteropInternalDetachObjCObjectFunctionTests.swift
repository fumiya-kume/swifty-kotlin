@testable import CompilerCore
import XCTest

final class NativeCInteropInternalDetachObjCObjectFunctionTests: XCTestCase {
    func testDetachObjCObjectSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected detachObjCObject() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropInternalPkg = ["kotlinx", "cinterop", "internal"].map { interner.intern($0) }

        let detachFQName = cinteropInternalPkg + [interner.intern("detachObjCObject")]
        let candidates = sema.symbols.lookupAll(fqName: detachFQName)
        let detach = try XCTUnwrap(candidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 1
                && signature.returnType == sema.types.unitType
        }, "kotlinx.cinterop.internal.detachObjCObject(obj: Any) must be registered")

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: detach))
        let flags = try XCTUnwrap(sema.symbols.symbol(detach)?.flags)

        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(
            sema.symbols.parentSymbol(for: detach),
            sema.symbols.lookup(fqName: cinteropInternalPkg)
        )
        XCTAssertEqual(signature.parameterTypes, [sema.types.anyType])
        XCTAssertEqual(signature.returnType, sema.types.unitType)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(signature.valueParameterIsVararg, [false])

        let parameterSymbol = try XCTUnwrap(signature.valueParameterSymbols.first)
        XCTAssertEqual(sema.symbols.symbol(parameterSymbol)?.name, interner.intern("obj"))
        XCTAssertEqual(sema.symbols.propertyType(for: parameterSymbol), sema.types.anyType)
    }

    func testDetachObjCObjectResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.internal.detachObjCObject

        fun releaseObjCObject(obj: Any) {
            detachObjCObject(obj)
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected detachObjCObject(obj) to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
