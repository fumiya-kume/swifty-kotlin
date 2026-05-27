@testable import CompilerCore
import XCTest

final class NativeCInteropStableRefSurfaceTests: XCTestCase {
    func testStableRefValueClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected StableRef surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: (["kotlinx", "cinterop"] + path).map { interner.intern($0) }),
                "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered"
            )
        }

        let stableRefSymbol = try cinteropSymbol("StableRef")
        let cPointedSymbol = try cinteropSymbol("CPointed")
        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: cPointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        let cOpaquePointerType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.out(cPointedType)],
            nullability: .nonNull
        )))
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: stableRefSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let stableRefType = sema.types.make(.classType(ClassType(
            classSymbol: stableRefSymbol,
            args: [.out(typeParameterType)],
            nullability: .nonNull
        )))
        let fqName = try XCTUnwrap(sema.symbols.symbol(stableRefSymbol)?.fqName)
        let flags = try XCTUnwrap(sema.symbols.symbol(stableRefSymbol)?.flags)

        XCTAssertEqual(sema.symbols.symbol(stableRefSymbol)?.kind, .class)
        XCTAssertTrue(flags.contains(.valueType))
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: stableRefSymbol), [.out])
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [sema.types.anyType])
        XCTAssertEqual(sema.symbols.propertyType(for: stableRefSymbol), stableRefType)
        XCTAssertEqual(sema.symbols.valueClassUnderlyingType(for: stableRefSymbol), cOpaquePointerType)

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes == [cOpaquePointerType] && $0.returnType == stableRefType
        })
        XCTAssertEqual(constructorSignature.valueParameterHasDefaultValues, [false])
    }

    func testStableRefMembersAndCompanionCreateAreRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected StableRef members to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let stableRefFQName = ["kotlinx", "cinterop", "StableRef"].map { interner.intern($0) }
        let stableRefSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: stableRefFQName))
        let cPointedSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "CPointed"].map { interner.intern($0) })
        )
        let cPointerSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "CPointer"].map { interner.intern($0) })
        )
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: stableRefSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let stableRefType = sema.types.make(.classType(ClassType(
            classSymbol: stableRefSymbol,
            args: [.out(typeParameterType)],
            nullability: .nonNull
        )))
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: cPointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        let cOpaquePointerType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.out(cPointedType)],
            nullability: .nonNull
        )))
        let memberExpectations: [(name: String, returnType: TypeID)] = [
            ("asCPointer", cOpaquePointerType),
            ("dispose", sema.types.unitType),
            ("get", typeParameterType),
        ]
        for expectation in memberExpectations {
            let member = try XCTUnwrap(sema.symbols.lookupAll(fqName: stableRefFQName + [interner.intern(expectation.name)])
                .first { symbol in
                    guard let signature = sema.symbols.functionSignature(for: symbol) else {
                        return false
                    }
                    return signature.receiverType == stableRefType
                        && signature.parameterTypes.isEmpty
                        && signature.returnType == expectation.returnType
                        && signature.typeParameterSymbols == [typeParameter]
                        && signature.classTypeParameterCount == 1
                })
            XCTAssertTrue(sema.symbols.symbol(member)?.flags.contains(.synthetic) == true)
        }

        let companionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: stableRefFQName + [interner.intern("Companion")]))
        let companionType = try XCTUnwrap(sema.symbols.propertyType(for: companionSymbol))
        let createSymbol = try XCTUnwrap(sema.symbols.lookupAll(
            fqName: stableRefFQName + [interner.intern("Companion"), interner.intern("create")]
        ).first { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol),
                  let createTypeParameter = signature.typeParameterSymbols.first
            else {
                return false
            }
            let createTypeParameterType = sema.types.make(.typeParam(TypeParamType(
                symbol: createTypeParameter,
                nullability: .nonNull
            )))
            let expectedReturnType = sema.types.make(.classType(ClassType(
                classSymbol: stableRefSymbol,
                args: [.out(createTypeParameterType)],
                nullability: .nonNull
            )))
            return signature.receiverType == companionType
                && signature.parameterTypes == [createTypeParameterType]
                && signature.returnType == expectedReturnType
                && signature.typeParameterUpperBoundsList == [[sema.types.anyType]]
        })
        XCTAssertTrue(sema.symbols.symbol(createSymbol)?.flags.isSuperset(of: [.synthetic, .static]) == true)
    }

    func testStableRefResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.COpaquePointer
        import kotlinx.cinterop.StableRef

        fun <T : Any> create(value: T): StableRef<T> {
            return StableRef.create(value)
        }

        fun <T : Any> pointer(ref: StableRef<T>): COpaquePointer {
            val value: T = ref.get()
            ref.dispose()
            return ref.asCPointer()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected StableRef to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
