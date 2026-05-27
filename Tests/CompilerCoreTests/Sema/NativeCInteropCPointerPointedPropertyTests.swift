@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerPointedPropertyTests: XCTestCase {
    func testCPointerPointedPropertySurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer.pointed surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        func cinteropSymbol(_ name: String) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: cinteropPkg + [interner.intern(name)]),
                "kotlinx.cinterop.\(name) must be registered"
            )
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CPointed"),
            args: [],
            nullability: .nonNull
        )))

        let pointedFQName = cinteropPkg + [interner.intern("pointed")]
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: pointedFQName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
            },
            "kotlinx.cinterop.CPointer<T>.pointed must be registered"
        )
        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        let typeParameter = try XCTUnwrap(getterSignature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), typeParameterType)
        XCTAssertEqual(sema.symbols.extensionPropertyReceiverType(for: propertySymbol), receiverType)
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cPointedType])
        XCTAssertEqual(getterSignature.receiverType, receiverType)
        XCTAssertEqual(getterSignature.parameterTypes, [])
        XCTAssertEqual(getterSignature.returnType, typeParameterType)
        XCTAssertEqual(getterSignature.typeParameterUpperBoundsList, [[cPointedType]])
        XCTAssertEqual(getterSignature.classTypeParameterCount, 0)
    }

    func testCPointerPointedPropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.pointed

        fun <T : CPointed> load(value: CPointer<T>): T {
            return value.pointed
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer.pointed to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
