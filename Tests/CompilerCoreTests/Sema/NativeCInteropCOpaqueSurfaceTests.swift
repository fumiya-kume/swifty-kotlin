@testable import CompilerCore
import XCTest

final class NativeCInteropCOpaqueSurfaceTests: XCTestCase {
    func testCOpaqueClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected COpaque surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ name: String) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: ["kotlinx", "cinterop", name].map { interner.intern($0) }),
                "kotlinx.cinterop.\(name) must be registered"
            )
        }

        let cOpaqueSymbol = try cinteropSymbol("COpaque")
        let cOpaqueType = sema.types.make(.classType(ClassType(
            classSymbol: cOpaqueSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("NativePtr"),
            args: [],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.symbol(cOpaqueSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.symbol(cOpaqueSymbol)?.flags.contains(.abstractType) == true)
        XCTAssertEqual(sema.symbols.propertyType(for: cOpaqueSymbol), cOpaqueType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cOpaqueSymbol), [try cinteropSymbol("CPointed")])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cOpaqueSymbol), [try cinteropSymbol("CPointed")])

        let fqName = try XCTUnwrap(sema.symbols.symbol(cOpaqueSymbol)?.fqName)
        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == cOpaqueType
        })
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [false])
    }

    func testCOpaqueResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.COpaque

        fun pass(value: COpaque): COpaque {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected COpaque to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
