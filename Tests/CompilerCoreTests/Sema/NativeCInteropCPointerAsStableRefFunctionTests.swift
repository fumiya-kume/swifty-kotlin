@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerAsStableRefFunctionTests: XCTestCase {
    func testCPointerAsStableRefFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer.asStableRef<T>() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let stableRefSymbol = try cinteropSymbol("StableRef")
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.star],
            nullability: .nonNull
        )))
        let asStableRefFQName = cinteropPkg + [interner.intern("asStableRef")]
        let asStableRef = try XCTUnwrap(sema.symbols.lookupAll(fqName: asStableRefFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.typeParameterSymbols.count == 1
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: asStableRef))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: stableRefSymbol,
            args: [.out(typeParameterType)],
            nullability: .nonNull
        )))
        let flags = try XCTUnwrap(sema.symbols.symbol(asStableRef)?.flags)
        let typeParameterFlags = try XCTUnwrap(sema.symbols.symbol(typeParameter)?.flags)

        XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        XCTAssertEqual(sema.symbols.parentSymbol(for: asStableRef), sema.symbols.lookup(fqName: cinteropPkg))
        XCTAssertEqual(signature.returnType, expectedReturnType)
        XCTAssertEqual(signature.reifiedTypeParameterIndices, [0])
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[sema.types.anyType]])
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [sema.types.anyType])
        XCTAssertTrue(typeParameterFlags.isSuperset(of: [.synthetic, .reifiedTypeParameter]))
        XCTAssertEqual(sema.symbols.parentSymbol(for: typeParameter), asStableRef)
    }

    func testCPointerAsStableRefFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.StableRef
        import kotlinx.cinterop.asStableRef

        fun restore(pointer: CPointer<*>): StableRef<String> {
            return pointer.asStableRef<String>()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer.asStableRef<String>() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
