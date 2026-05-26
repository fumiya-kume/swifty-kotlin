@testable import CompilerCore
import XCTest

final class NativeCInteropCOpaquePointerVarTypeAliasTests: XCTestCase {
    func testCOpaquePointerVarTypeAliasSurface() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected COpaquePointerVar typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPackage = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let aliasSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("COpaquePointerVar")])
        )
        let cPointerVarOfSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CPointerVarOf")])
        )
        let cOpaquePointerAlias = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("COpaquePointer")])
        )
        let cOpaquePointerType = try XCTUnwrap(sema.symbols.typeAliasUnderlyingType(for: cOpaquePointerAlias))
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(cOpaquePointerType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.symbol(aliasSymbol)?.kind, .typeAlias)
        XCTAssertEqual(sema.symbols.typeAliasTypeParameters(for: aliasSymbol), [])
        XCTAssertEqual(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol), expectedUnderlying)
    }

    func testCOpaquePointerVarResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.COpaquePointerVar

        fun pass(value: COpaquePointerVar): COpaquePointerVar {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected COpaquePointerVar typealias to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
