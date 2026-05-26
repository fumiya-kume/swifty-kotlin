@testable import CompilerCore
import XCTest

final class NativeCInteropNativeHeapPropertyTests: XCTestCase {
    func testNativeHeapPropertySurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected nativeHeap surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let nativeFreeablePlacementSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("NativeFreeablePlacement")]),
            "NativeFreeablePlacement must be registered"
        )
        let nativeFreeablePlacementType = sema.types.make(.classType(ClassType(
            classSymbol: nativeFreeablePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("nativeHeap")]),
            "kotlinx.cinterop.nativeHeap must be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(propertySymbol)?.kind, .property)
        XCTAssertEqual(sema.symbols.parentSymbol(for: propertySymbol), sema.symbols.lookup(fqName: cinteropPkg))
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), nativeFreeablePlacementType)
    }

    func testNativeHeapPropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.NativeFreeablePlacement
        import kotlinx.cinterop.nativeHeap

        fun heap(): NativeFreeablePlacement {
            return nativeHeap
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected nativeHeap to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
