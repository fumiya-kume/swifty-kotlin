@testable import CompilerCore
import XCTest

final class NativeCInteropCValuesSurfaceTests: XCTestCase {
    func testCValuesClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CValues surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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

        let cValuesSymbol = try cinteropSymbol("CValues")
        let cValuesRefSymbol = try cinteropSymbol("CValuesRef")
        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cVariableType = try cinteropType("CVariable")
        let autofreeScopeType = try cinteropType("AutofreeScope")
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: cValuesSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let cValuesType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let cPointerType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let fqName = try XCTUnwrap(sema.symbols.symbol(cValuesSymbol)?.fqName)
        let flags = try XCTUnwrap(sema.symbols.symbol(cValuesSymbol)?.flags)

        XCTAssertEqual(sema.symbols.symbol(cValuesSymbol)?.kind, .class)
        XCTAssertTrue(flags.contains(.abstractType))
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: cValuesSymbol), [.invariant])
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cVariableType])
        XCTAssertEqual(sema.symbols.propertyType(for: cValuesSymbol), cValuesType)
        XCTAssertEqual(sema.symbols.directSupertypes(for: cValuesSymbol), [cValuesRefSymbol])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: cValuesSymbol), [cValuesRefSymbol])
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: cValuesSymbol, supertype: cValuesRefSymbol),
            [.invariant(typeParameterType)]
        )
        XCTAssertEqual(
            sema.types.nominalSupertypeTypeArgs(for: cValuesSymbol, supertype: cValuesRefSymbol),
            [.invariant(typeParameterType)]
        )

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes.isEmpty && $0.returnType == cValuesType
        })
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [])

        let align = try XCTUnwrap(sema.symbols.lookup(fqName: fqName + [interner.intern("align")]))
        XCTAssertEqual(sema.symbols.propertyType(for: align), sema.types.intType)
        XCTAssertTrue(sema.symbols.symbol(align)?.flags.contains(.abstractType) == true)

        let size = try XCTUnwrap(sema.symbols.lookup(fqName: fqName + [interner.intern("size")]))
        XCTAssertEqual(sema.symbols.propertyType(for: size), sema.types.intType)
        XCTAssertTrue(sema.symbols.symbol(size)?.flags.contains(.abstractType) == true)

        let getPointer = try XCTUnwrap(sema.symbols.lookupAll(fqName: fqName + [interner.intern("getPointer")])
            .compactMap { sema.symbols.functionSignature(for: $0) }
            .first {
                $0.receiverType == cValuesType &&
                    $0.parameterTypes == [autofreeScopeType] &&
                    $0.returnType == cPointerType
            })
        XCTAssertEqual(getPointer.typeParameterSymbols, [typeParameter])
        XCTAssertEqual(getPointer.typeParameterUpperBoundsList, [[cVariableType]])
        XCTAssertEqual(getPointer.classTypeParameterCount, 1)

        let placeSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fqName + [interner.intern("place")])
            .first {
                guard let signature = sema.symbols.functionSignature(for: $0) else {
                    return false
                }
                return signature.receiverType == cValuesType &&
                    signature.parameterTypes == [cPointerType] &&
                    signature.returnType == cPointerType
            })
        let place = try XCTUnwrap(sema.symbols.functionSignature(for: placeSymbol))
        XCTAssertEqual(place.typeParameterSymbols, [typeParameter])
        XCTAssertEqual(place.typeParameterUpperBoundsList, [[cVariableType]])
        XCTAssertEqual(place.classTypeParameterCount, 1)
        XCTAssertTrue(sema.symbols.symbol(placeSymbol)?.flags.contains(.abstractType) == true)
        XCTAssertTrue(
            sema.symbols.annotations(for: placeSymbol).contains {
                $0.annotationFQName == "kotlin.IgnorableReturnValue"
            },
            "CValues.place should carry @IgnorableReturnValue"
        )
    }

    func testCValuesMembersResolveInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.AutofreeScope
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.CValuesRef
        import kotlinx.cinterop.CVariable

        fun <T : CVariable> readMetadata(value: CValues<T>): Int {
            return value.align + value.size
        }

        fun <T : CVariable> copy(value: CValues<T>, scope: AutofreeScope, pointer: CPointer<T>): CPointer<T> {
            value.getPointer(scope)
            return value.place(pointer)
        }

        fun <T : CVariable> upcast(value: CValues<T>): CValuesRef<T> {
            return value
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CValues members to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
