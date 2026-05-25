@testable import CompilerCore
import XCTest

final class NativeCInteropCOpaquePointerTypeAliasTests: XCTestCase {
    func testCOpaquePointerTypeAliasSurface() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected COpaquePointer typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPackage = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let aliasSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("COpaquePointer")])
        )
        let cPointerSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CPointer")])
        )
        let cPointedSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CPointed")])
        )
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: cPointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.out(cPointedType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.symbol(aliasSymbol)?.kind, .typeAlias)
        XCTAssertEqual(sema.symbols.typeAliasTypeParameters(for: aliasSymbol), [])
        XCTAssertEqual(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol), expectedUnderlying)
    }

    func testCOpaquePointerResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.COpaquePointer

        fun pass(value: COpaquePointer): COpaquePointer {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected COpaquePointer typealias to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
