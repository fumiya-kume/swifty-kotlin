@testable import CompilerCore
import XCTest

final class NativeCInteropCArrayPointerTypeAliasTests: XCTestCase {
    func testCArrayPointerTypeAliasSurface() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CArrayPointer typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPackage = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let aliasSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CArrayPointer")])
        )
        let cPointerSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CPointer")])
        )
        let typeParameter = try XCTUnwrap(sema.symbols.typeAliasTypeParameters(for: aliasSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.symbol(aliasSymbol)?.kind, .typeAlias)
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol), expectedUnderlying)
    }

    func testCArrayPointerResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CArrayPointer
        import kotlinx.cinterop.CPointed

        fun pass(value: CArrayPointer<CPointed>): CArrayPointer<CPointed> {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CArrayPointer typealias to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
