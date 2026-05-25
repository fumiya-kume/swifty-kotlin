@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerSurfaceTests: XCTestCase {
    func testCPointerClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ name: String) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: ["kotlinx", "cinterop", name].map { interner.intern($0) }),
                "kotlinx.cinterop.\(name) must be registered"
            )
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cValuesRefSymbol = try cinteropSymbol("CValuesRef")
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CPointed"),
            args: [],
            nullability: .nonNull
        )))
        let autofreeScopeType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("AutofreeScope"),
            args: [],
            nullability: .nonNull
        )))
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: cPointerSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let cPointerType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.symbol(cPointerSymbol)?.kind, .class)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: cPointerSymbol), [.invariant])
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cPointedType])
        XCTAssertEqual(sema.symbols.propertyType(for: cPointerSymbol), cPointerType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cPointerSymbol), [cValuesRefSymbol])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cPointerSymbol), [cValuesRefSymbol])
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: cPointerSymbol, supertype: cValuesRefSymbol),
            [.invariant(typeParameterType)]
        )
        XCTAssertEqual(
            sema.types.nominalSupertypeTypeArgs(for: cPointerSymbol, supertype: cValuesRefSymbol),
            [.invariant(typeParameterType)]
        )

        let fqName = try XCTUnwrap(sema.symbols.symbol(cPointerSymbol)?.fqName)
        let getPointer = try XCTUnwrap(sema.symbols.lookupAll(fqName: fqName + [interner.intern("getPointer")])
            .compactMap { sema.symbols.functionSignature(for: $0) }
            .first {
                $0.receiverType == cPointerType &&
                    $0.parameterTypes == [autofreeScopeType] &&
                    $0.returnType == cPointerType
            })
        XCTAssertEqual(getPointer.typeParameterSymbols, [typeParameter])
        XCTAssertEqual(getPointer.typeParameterUpperBoundsList, [[cPointedType]])
        XCTAssertEqual(getPointer.classTypeParameterCount, 1)
    }

    func testCPointerGetPointerResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.AutofreeScope
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CPointer

        fun <T : CPointed> pass(value: CPointer<T>, scope: AutofreeScope): CPointer<T> {
            return value.getPointer(scope)
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer.getPointer to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
