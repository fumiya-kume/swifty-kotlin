@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerRawValuePropertyTests: XCTestCase {
    func testCPointerRawValuePropertySurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer.rawValue surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        func cinteropSymbol(_ name: String) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: cinteropPkg + [interner.intern(name)]),
                "kotlinx.cinterop.\(name) must be registered"
            )
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("NativePtr"),
            args: [],
            nullability: .nonNull
        )))
        let cPointerFQName = try XCTUnwrap(sema.symbols.symbol(cPointerSymbol)?.fqName)
        let rawValueSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cPointerFQName + [interner.intern("rawValue")]),
            "CPointer.rawValue must be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(rawValueSymbol)?.kind, .property)
        XCTAssertEqual(sema.symbols.parentSymbol(for: rawValueSymbol), cPointerSymbol)
        XCTAssertEqual(sema.symbols.propertyType(for: rawValueSymbol), nativePtrType)
    }

    func testCPointerRawValuePropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.NativePtr

        fun <T : CPointed> raw(value: CPointer<T>): NativePtr {
            return value.rawValue
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer.rawValue to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
