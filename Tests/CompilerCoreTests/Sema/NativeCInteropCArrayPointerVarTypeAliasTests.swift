@testable import CompilerCore
import XCTest

final class NativeCInteropCArrayPointerVarTypeAliasTests: XCTestCase {
    func testCArrayPointerVarTypeAliasSurface() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CArrayPointerVar typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPackage = ["kotlinx", "cinterop"].map { interner.intern($0) }
        let aliasSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CArrayPointerVar")])
        )
        let cPointerVarSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPackage + [interner.intern("CPointerVar")])
        )
        let typeParameter = try XCTUnwrap(sema.symbols.typeAliasTypeParameters(for: aliasSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: cPointerVarSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.symbol(aliasSymbol)?.kind, .typeAlias)
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol), expectedUnderlying)
    }

    func testCArrayPointerVarResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CArrayPointerVar
        import kotlinx.cinterop.CPointed

        fun pass(value: CArrayPointerVar<CPointed>): CArrayPointerVar<CPointed> {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CArrayPointerVar typealias to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
