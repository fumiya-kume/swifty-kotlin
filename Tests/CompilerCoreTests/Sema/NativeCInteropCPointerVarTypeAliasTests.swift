@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerVarTypeAliasTests: XCTestCase {
    func testCPointerVarTypeAliasSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointerVar typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ name: String) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: ["kotlinx", "cinterop", name].map { interner.intern($0) }),
                "kotlinx.cinterop.\(name) must be registered"
            )
        }

        let aliasSymbol = try cinteropSymbol("CPointerVar")
        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cPointerVarOfSymbol = try cinteropSymbol("CPointerVarOf")
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CPointed"),
            args: [],
            nullability: .nonNull
        )))
        let typeParameter = try XCTUnwrap(sema.symbols.typeAliasTypeParameters(for: aliasSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let pointerType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(pointerType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.symbol(aliasSymbol)?.kind, .typeAlias)
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cPointedType])
        XCTAssertEqual(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol), expectedUnderlying)
    }

    func testCPointerVarResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CPointerVar

        fun pass(value: CPointerVar<CPointed>): CPointerVar<CPointed> {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointerVar typealias to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
