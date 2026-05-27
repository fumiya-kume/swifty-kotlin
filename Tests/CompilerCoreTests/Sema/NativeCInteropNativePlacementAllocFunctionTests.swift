@testable import CompilerCore
import XCTest

final class NativeCInteropNativePlacementAllocFunctionTests: XCTestCase {
    func testNativePlacementAllocFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativePlacement.alloc<T>() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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

        let cVariableType = try cinteropType("CVariable")
        let nativePlacementType = try cinteropType("NativePlacement")
        let allocFQName = cinteropPkg + [interner.intern("alloc")]
        let allocCandidates = sema.symbols.lookupAll(fqName: allocFQName)

        let alloc = try XCTUnwrap(allocCandidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nativePlacementType
                && signature.parameterTypes.isEmpty
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: alloc))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let flags = try XCTUnwrap(sema.symbols.symbol(alloc)?.flags)
        let typeParameterFlags = try XCTUnwrap(sema.symbols.symbol(typeParameter)?.flags)

        XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        XCTAssertEqual(sema.symbols.parentSymbol(for: alloc), sema.symbols.lookup(fqName: cinteropPkg))
        XCTAssertEqual(signature.returnType, typeParameterType)
        XCTAssertEqual(signature.reifiedTypeParameterIndices, [0])
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[cVariableType]])
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cVariableType])
        XCTAssertTrue(typeParameterFlags.isSuperset(of: [.synthetic, .reifiedTypeParameter]))
        XCTAssertEqual(sema.symbols.parentSymbol(for: typeParameter), alloc)
    }

    func testNativePlacementAllocFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.NativePlacement
        import kotlinx.cinterop.alloc

        fun allocateByte(placement: NativePlacement): ByteVar {
            return placement.alloc<ByteVar>()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativePlacement.alloc<ByteVar>() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
