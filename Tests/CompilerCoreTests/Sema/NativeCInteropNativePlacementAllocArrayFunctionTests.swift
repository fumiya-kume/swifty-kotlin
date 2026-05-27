@testable import CompilerCore
import XCTest

final class NativeCInteropNativePlacementAllocArrayFunctionTests: XCTestCase {
    func testNativePlacementAllocArrayFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativePlacement.allocArray<T>(length) surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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
        func allocArraySignature(parameterType: TypeID) throws -> (SymbolID, FunctionSignature) {
            let functionFQName = cinteropPkg + [interner.intern("allocArray")]
            let nativePlacementType = try cinteropType("NativePlacement")
            let candidates = sema.symbols.lookupAll(fqName: functionFQName)
            let symbol = try XCTUnwrap(candidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == nativePlacementType
                    && signature.parameterTypes == [parameterType]
                    && signature.typeParameterSymbols.count == 1
            })
            return (symbol, try XCTUnwrap(sema.symbols.functionSignature(for: symbol)))
        }
        func assertAllocArrayOverload(
            parameterType: TypeID,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let cVariableType = try cinteropType("CVariable")
            let cPointerSymbol = try cinteropSymbol("CPointer")
            let (symbol, signature) = try allocArraySignature(parameterType: parameterType)
            let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first, file: file, line: line)
            let typeParameterType = sema.types.make(.typeParam(TypeParamType(
                symbol: typeParameter,
                nullability: .nonNull
            )))
            let expectedReturnType = sema.types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(typeParameterType)],
                nullability: .nonNull
            )))
            let flags = try XCTUnwrap(sema.symbols.symbol(symbol)?.flags, file: file, line: line)
            let typeParameterFlags = try XCTUnwrap(sema.symbols.symbol(typeParameter)?.flags, file: file, line: line)

            XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction]), file: file, line: line)
            XCTAssertEqual(signature.returnType, expectedReturnType, file: file, line: line)
            XCTAssertEqual(signature.reifiedTypeParameterIndices, [0], file: file, line: line)
            XCTAssertEqual(signature.typeParameterUpperBoundsList, [[cVariableType]], file: file, line: line)
            XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cVariableType], file: file, line: line)
            XCTAssertTrue(
                typeParameterFlags.isSuperset(of: [.synthetic, .reifiedTypeParameter]),
                file: file,
                line: line
            )
            XCTAssertEqual(sema.symbols.parentSymbol(for: typeParameter), symbol, file: file, line: line)
        }

        try assertAllocArrayOverload(parameterType: sema.types.longType)
        try assertAllocArrayOverload(parameterType: sema.types.intType)
    }

    func testNativePlacementAllocArrayFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CArrayPointer
        import kotlinx.cinterop.NativePlacement
        import kotlinx.cinterop.allocArray

        fun allocateByteArrayLong(placement: NativePlacement): CArrayPointer<ByteVar> {
            return placement.allocArray<ByteVar>(4L)
        }

        fun allocateByteArrayInt(placement: NativePlacement): CArrayPointer<ByteVar> {
            return placement.allocArray<ByteVar>(4)
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NativePlacement.allocArray<ByteVar>(length) to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
