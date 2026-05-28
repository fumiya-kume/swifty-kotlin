@testable import CompilerCore
import XCTest

final class NativeCInteropUsePinnedFunctionTests: XCTestCase {
    func testUsePinnedFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected usePinned surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let pinnedSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("Pinned")]),
            "kotlinx.cinterop.Pinned must be registered"
        )

        let usePinnedFQName = cinteropPkg + [interner.intern("usePinned")]
        let usePinnedSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: usePinnedFQName).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.parameterTypes.count == 1
                    && signature.typeParameterSymbols.count == 2
            },
            "kotlinx.cinterop.usePinned must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: usePinnedSymbol))
        let flags = try XCTUnwrap(sema.symbols.symbol(usePinnedSymbol)?.flags)

        // Two type parameters: T and R
        XCTAssertEqual(signature.typeParameterSymbols.count, 2)
        let tParamSymbol = signature.typeParameterSymbols[0]
        let rParamSymbol = signature.typeParameterSymbols[1]

        XCTAssertEqual(sema.symbols.symbol(tParamSymbol)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.symbol(rParamSymbol)?.name, interner.intern("R"))
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: tParamSymbol), [sema.types.anyType])
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: rParamSymbol), [sema.types.anyType])

        // Receiver is T
        let tParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))
        XCTAssertEqual(signature.receiverType, tParamType)

        // Return type is R
        let rParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: rParamSymbol,
            nullability: .nonNull
        )))
        XCTAssertEqual(signature.returnType, rParamType)

        // One parameter: block: (Pinned<T>) -> R
        XCTAssertEqual(signature.parameterTypes.count, 1)
        let pinnedTType = sema.types.make(.classType(ClassType(
            classSymbol: pinnedSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))
        let expectedBlockType = sema.types.make(.functionType(FunctionType(
            params: [pinnedTType],
            returnType: rParamType
        )))
        XCTAssertEqual(signature.parameterTypes[0], expectedBlockType)

        // Flags
        XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        XCTAssertEqual(sema.symbols.parentSymbol(for: usePinnedSymbol), sema.symbols.lookup(fqName: cinteropPkg))
    }

    func testUsePinnedFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.Pinned
        import kotlinx.cinterop.usePinned

        fun pinString(value: String): Pinned<String> {
            return value.usePinned { pinned -> pinned }
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected usePinned to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
