@testable import CompilerCore
import XCTest

final class NativeCInteropByteVarTypeAliasTests: XCTestCase {
    func testByteVarTypeAliasSurface() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ByteVar typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        func symbol(_ fqPath: [String]) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) }),
                "\(fqPath.joined(separator: ".")) must be registered"
            )
        }

        let aliasSymbol = try symbol(["kotlinx", "cinterop", "ByteVar"])
        let byteVarOfSymbol = try symbol(["kotlinx", "cinterop", "ByteVarOf"])
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: byteVarOfSymbol,
            args: [.invariant(sema.types.intType)],
            nullability: .nonNull
        )))
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: byteVarOfSymbol)

        XCTAssertEqual(sema.symbols.symbol(aliasSymbol)?.kind, .typeAlias)
        XCTAssertEqual(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol), expectedUnderlying)
        XCTAssertEqual(sema.symbols.symbol(byteVarOfSymbol)?.kind, .class)
        XCTAssertEqual(typeParameters.count, 1)
        XCTAssertEqual(sema.symbols.symbol(try XCTUnwrap(typeParameters.first))?.name, interner.intern("T"))
    }

    func testByteVarResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar

        fun roundtrip(value: ByteVar): ByteVar {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected ByteVar typealias to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
