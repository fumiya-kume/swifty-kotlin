@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerVarOfSurfaceTests: XCTestCase {
    func testCPointerVarOfClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointerVarOf surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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

        let cPointerVarOfSymbol = try cinteropSymbol("CPointerVarOf")
        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cVariableSymbol = try cinteropSymbol("CVariable")
        let cVariableTypeSymbol = try cinteropSymbol("CVariable", "Type")
        let nativePtrType = try cinteropType("NativePtr")
        let fqName = try XCTUnwrap(sema.symbols.symbol(cPointerVarOfSymbol)?.fqName)
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: cPointerVarOfSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let cPointerVarOfType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let cPointerStarType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.star],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.symbol(cPointerVarOfSymbol)?.kind, .class)
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cPointerStarType])
        XCTAssertEqual(sema.symbols.propertyType(for: cPointerVarOfSymbol), cPointerVarOfType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cPointerVarOfSymbol), [cVariableSymbol])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cPointerVarOfSymbol), [cVariableSymbol])

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == cPointerVarOfType
        })
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [false])

        let companionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName + [interner.intern("Companion")]))
        XCTAssertEqual(sema.symbols.symbol(companionSymbol)?.kind, .object)
        XCTAssertEqual(sema.symbols.companionObjectSymbol(for: cPointerVarOfSymbol), companionSymbol)
        XCTAssertEqual(sema.symbols.directSupertypes(for: companionSymbol), [cVariableTypeSymbol])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: companionSymbol), [cVariableTypeSymbol])
    }

    func testCPointerVarOfResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.CPointerVarOf

        fun pass(value: CPointerVarOf<CPointer<CPointed>>): CPointerVarOf<CPointer<CPointed>> {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointerVarOf to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
