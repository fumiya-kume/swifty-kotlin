@testable import CompilerCore
import XCTest

final class NativeCInteropCEnumSurfaceTests: XCTestCase {
    func testCEnumInterfaceSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CEnum surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPackage = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let cEnumSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CEnum")])
        )
        let valueSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CEnum"), interner.intern("value")])
        )
        let deprecated = sema.symbols.annotations(for: cEnumSymbol).first {
            $0.annotationFQName == "kotlin.Deprecated"
        }

        XCTAssertEqual(sema.symbols.symbol(cEnumSymbol)?.kind, .interface)
        XCTAssertEqual(sema.symbols.propertyType(for: cEnumSymbol), sema.types.make(.classType(ClassType(
            classSymbol: cEnumSymbol,
            args: [],
            nullability: .nonNull
        ))))
        XCTAssertNotNil(deprecated)
        XCTAssertEqual(deprecated?.arguments, ["message = \"Will be removed.\""])
        XCTAssertEqual(sema.symbols.symbol(valueSymbol)?.kind, .property)
        XCTAssertEqual(sema.symbols.propertyType(for: valueSymbol), sema.types.anyType)
        XCTAssertTrue(sema.symbols.symbol(valueSymbol)?.flags.contains(.abstractType) == true)
    }

    func testCEnumValuePropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CEnum

        @Suppress("DEPRECATION")
        fun readValue(value: CEnum): Any {
            return value.value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CEnum.value to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
