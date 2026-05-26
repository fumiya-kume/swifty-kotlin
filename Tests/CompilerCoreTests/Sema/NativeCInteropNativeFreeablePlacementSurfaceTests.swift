@testable import CompilerCore
import XCTest

final class NativeCInteropNativeFreeablePlacementSurfaceTests: XCTestCase {
    func testNativeFreeablePlacementInterfaceSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativeFreeablePlacement surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: (["kotlinx", "cinterop"] + path).map { interner.intern($0) }),
                "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered"
            )
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }
        func cinteropType(_ path: String...) throws -> TypeID {
            sema.types.make(.classType(ClassType(
                classSymbol: try cinteropSymbol(path),
                args: [],
                nullability: .nonNull
            )))
        }

        let nativeFreeablePlacementSymbol = try cinteropSymbol("NativeFreeablePlacement")
        let nativePlacementSymbol = try cinteropSymbol("NativePlacement")
        let nativeFreeablePlacementType = try cinteropType("NativeFreeablePlacement")

        XCTAssertEqual(sema.symbols.symbol(nativeFreeablePlacementSymbol)?.kind, .interface)
        XCTAssertEqual(sema.symbols.propertyType(for: nativeFreeablePlacementSymbol), nativeFreeablePlacementType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: nativeFreeablePlacementSymbol), [nativePlacementSymbol])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: nativeFreeablePlacementSymbol), [nativePlacementSymbol])
    }

    func testNativeFreeablePlacementResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.NativeFreeablePlacement
        import kotlinx.cinterop.NativePlacement

        fun upcast(value: NativeFreeablePlacement): NativePlacement {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativeFreeablePlacement to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
