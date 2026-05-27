@testable import CompilerCore
import XCTest

final class NativeCInteropCPointerPlusFunctionTests: XCTestCase {
    func testCPointerPlusFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer.plus surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
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
        let plusFQName = cinteropPkg + [interner.intern("plus")]
        let plusCandidates = sema.symbols.lookupAll(fqName: plusFQName)
        let byteVarOfUpperBound = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("ByteVarOf"),
            args: [.star],
            nullability: .nonNull
        )))
        let cPointerVarOfUpperBound = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CPointerVarOf"),
            args: [.star],
            nullability: .nonNull
        )))

        func assertPlusOverload(
            indexType: TypeID,
            upperBound: TypeID,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let plusSymbol = try XCTUnwrap(plusCandidates.first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.parameterTypes == [indexType]
                    && signature.typeParameterUpperBoundsList == [[upperBound]]
            }, file: file, line: line)
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: plusSymbol), file: file, line: line)
            let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first, file: file, line: line)
            let typeParameterType = sema.types.make(.typeParam(TypeParamType(
                symbol: typeParameter,
                nullability: .nonNull
            )))
            let expectedPointerType = sema.types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(typeParameterType)],
                nullability: .nullable
            )))
            let parameterSymbol = try XCTUnwrap(signature.valueParameterSymbols.first, file: file, line: line)
            let flags = try XCTUnwrap(sema.symbols.symbol(plusSymbol)?.flags, file: file, line: line)

            XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction, .operatorFunction]), file: file, line: line)
            XCTAssertEqual(signature.receiverType, expectedPointerType, file: file, line: line)
            XCTAssertEqual(signature.returnType, expectedPointerType, file: file, line: line)
            XCTAssertTrue(signature.reifiedTypeParameterIndices.isEmpty, file: file, line: line)
            XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [upperBound], file: file, line: line)
            XCTAssertEqual(sema.symbols.symbol(parameterSymbol)?.name, interner.intern("index"), file: file, line: line)
            XCTAssertEqual(sema.symbols.propertyType(for: parameterSymbol), indexType, file: file, line: line)
        }

        try assertPlusOverload(indexType: sema.types.intType, upperBound: byteVarOfUpperBound)
        try assertPlusOverload(indexType: sema.types.longType, upperBound: byteVarOfUpperBound)
        try assertPlusOverload(indexType: sema.types.intType, upperBound: cPointerVarOfUpperBound)
        try assertPlusOverload(indexType: sema.types.longType, upperBound: cPointerVarOfUpperBound)
    }

    func testCPointerPlusFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer

        fun plusInt(value: CPointer<ByteVar>?): CPointer<ByteVar>? {
            return value + 1
        }

        fun plusLong(value: CPointer<ByteVar>?): CPointer<ByteVar>? {
            return value + 1L
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CPointer.plus to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
