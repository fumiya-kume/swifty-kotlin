@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerPlusFunctionTests: XCTestCase {
    func testCPointerPlusOperatorSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer<T>?.plus(index: Long) surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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
        func cinteropType(_ path: String...) throws -> TypeID {
            sema.types.make(.classType(ClassType(
                classSymbol: try cinteropSymbol(path),
                args: [],
                nullability: .nonNull
            )))
        }

        let cPointedType = try cinteropType("CPointed")
        let cPointerSymbol = try cinteropSymbol("CPointer")
        let plusFQName = cinteropPkg + [interner.intern("plus")]
        let plusCandidates = sema.symbols.lookupAll(fqName: plusFQName)

        let plus = try XCTUnwrap(plusCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClassType) = sema.types.kind(of: receiverType),
                  receiverClassType.classSymbol == cPointerSymbol,
                  receiverClassType.nullability == .nullable
            else {
                return false
            }
            return signature.parameterTypes == [sema.types.longType]
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: plus))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedReceiverType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nullable
        )))
        let flags = try XCTUnwrap(sema.symbols.symbol(plus)?.flags)

        XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction, .operatorFunction]))
        XCTAssertEqual(sema.symbols.parentSymbol(for: plus), sema.symbols.lookup(fqName: cinteropPkg))
        XCTAssertEqual(signature.receiverType, expectedReceiverType)
        XCTAssertEqual(signature.returnType, expectedReceiverType)
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[cPointedType]])
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cPointedType])
        XCTAssertEqual(sema.symbols.parentSymbol(for: typeParameter), plus)
    }

    func testCPointerPlusOperatorResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.plus

        fun shiftPointer(p: CPointer<ByteVar>?): CPointer<ByteVar>? {
            return p + 4L
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer<ByteVar>? + Long to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
