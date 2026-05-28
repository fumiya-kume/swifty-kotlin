@testable import CompilerCore
import XCTest

final class NativeCInteropListCPointerToCValuesFunctionTests: XCTestCase {
    func testListCPointerToCValuesFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected List<CPointer<T>?>.toCValues() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) }),
                "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered"
            )
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }

        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CPointed"),
            args: [],
            nullability: .nonNull
        )))
        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cPointerVarOfSymbol = try cinteropSymbol("CPointerVarOf")
        let cValuesSymbol = try cinteropSymbol("CValues")
        let listSymbol = try XCTUnwrap(
            sema.symbols.lookup(
                fqName: ["kotlin", "collections", "List"].map { interner.intern($0) }
            ),
            "kotlin.collections.List must be registered"
        )

        let toCValuesFQName = cinteropPkg + [interner.intern("toCValues")]
        let toCValuesCandidates = sema.symbols.lookupAll(fqName: toCValuesFQName)

        let toCValues = try XCTUnwrap(toCValuesCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            guard signature.parameterTypes.isEmpty,
                  signature.typeParameterSymbols.count == 1
            else {
                return false
            }
            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClassType) = sema.types.kind(of: receiverType),
                  receiverClassType.classSymbol == listSymbol
            else {
                return false
            }
            return true
        }, "List<CPointer<T>?>.toCValues() must be registered")
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: toCValues))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let nullableCPointerElementType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nullable
        )))
        let expectedReceiverType = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(nullableCPointerElementType)],
            nullability: .nonNull
        )))
        let nonNullCPointerElementType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let expectedCPointerVarType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(nonNullCPointerElementType)],
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(expectedCPointerVarType)],
            nullability: .nonNull
        )))
        let flags = try XCTUnwrap(sema.symbols.symbol(toCValues)?.flags)
        let typeParameterFlags = try XCTUnwrap(sema.symbols.symbol(typeParameter)?.flags)

        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: toCValues), sema.symbols.lookup(fqName: cinteropPkg))
        XCTAssertEqual(signature.receiverType, expectedReceiverType)
        XCTAssertEqual(signature.returnType, expectedReturnType)
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[cPointedType]])
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cPointedType])
        XCTAssertTrue(typeParameterFlags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: typeParameter), toCValues)
    }

    func testListCPointerToCValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.CPointerVar
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.toCValues

        fun toPointers(list: List<CPointer<ByteVar>?>): CValues<CPointerVar<ByteVar>> {
            return list.toCValues()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected List<CPointer<ByteVar>?>.toCValues() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
