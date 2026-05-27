@testable import CompilerCore
import XCTest

final class NativeCInteropPinFunctionTests: XCTestCase {
    func testPinFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected pin surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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

        let pinnedSymbol = try cinteropSymbol("Pinned")
        let pinnedTypeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: pinnedSymbol).first)
        let pinnedTypeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: pinnedTypeParameter,
            nullability: .nonNull
        )))
        let pinnedType = sema.types.make(.classType(ClassType(
            classSymbol: pinnedSymbol,
            args: [.invariant(pinnedTypeParameterType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.symbol(pinnedSymbol)?.kind, .class)
        XCTAssertEqual(sema.symbols.propertyType(for: pinnedSymbol), pinnedType)
        XCTAssertEqual(sema.symbols.symbol(pinnedTypeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: pinnedTypeParameter), [sema.types.anyType])
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: pinnedSymbol), [.invariant])

        let pinFQName = cinteropPkg + [interner.intern("pin")]
        let pinSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: pinFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes.isEmpty
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: pinSymbol))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: pinnedSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let flags = try XCTUnwrap(sema.symbols.symbol(pinSymbol)?.flags)

        XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        XCTAssertEqual(signature.receiverType, typeParameterType)
        XCTAssertEqual(signature.returnType, expectedReturnType)
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[sema.types.anyType]])
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [sema.types.anyType])
        XCTAssertEqual(sema.symbols.parentSymbol(for: pinSymbol), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testPinFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.Pinned
        import kotlinx.cinterop.pin

        fun pinString(value: String): Pinned<String> {
            return value.pin()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected pin to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
