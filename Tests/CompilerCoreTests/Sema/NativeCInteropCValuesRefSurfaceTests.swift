@testable import CompilerCore
import XCTest

final class NativeCInteropCValuesRefSurfaceTests: XCTestCase {
    func testCValuesRefClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CValuesRef surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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

        let cValuesRefSymbol = try cinteropSymbol("CValuesRef")
        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cPointedType = try cinteropType("CPointed")
        let autofreeScopeType = try cinteropType("AutofreeScope")
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: cValuesRefSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let cValuesRefType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesRefSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let cPointerType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let fqName = try XCTUnwrap(sema.symbols.symbol(cValuesRefSymbol)?.fqName)
        let flags = try XCTUnwrap(sema.symbols.symbol(cValuesRefSymbol)?.flags)

        XCTAssertEqual(sema.symbols.symbol(cValuesRefSymbol)?.kind, .class)
        XCTAssertTrue(flags.contains(.abstractType))
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: cValuesRefSymbol), [.invariant])
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cPointedType])
        XCTAssertEqual(sema.symbols.propertyType(for: cValuesRefSymbol), cValuesRefType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cValuesRefSymbol), [])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cValuesRefSymbol), [])

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes.isEmpty && $0.returnType == cValuesRefType
        })
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [])

        let getPointerSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fqName + [interner.intern("getPointer")])
            .first {
                guard let signature = sema.symbols.functionSignature(for: $0) else {
                    return false
                }
                return signature.receiverType == cValuesRefType &&
                    signature.parameterTypes == [autofreeScopeType] &&
                    signature.returnType == cPointerType
            })
        let getPointer = try XCTUnwrap(sema.symbols.functionSignature(for: getPointerSymbol))
        XCTAssertEqual(getPointer.typeParameterSymbols, [typeParameter])
        XCTAssertEqual(getPointer.typeParameterUpperBoundsList, [[cPointedType]])
        XCTAssertEqual(getPointer.classTypeParameterCount, 1)
        XCTAssertTrue(sema.symbols.symbol(getPointerSymbol)?.flags.contains(.abstractType) == true)
    }

    func testCValuesRefGetPointerResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.AutofreeScope
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.CValuesRef

        fun <T : CPointed> pass(value: CValuesRef<T>, scope: AutofreeScope): CPointer<T> {
            return value.getPointer(scope)
        }

        fun <T : CPointed> upcast(pointer: CPointer<T>): CValuesRef<T> {
            return pointer
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CValuesRef.getPointer to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
