@testable import CompilerCore
import XCTest

final class NativeCInteropZeroValueFunctionTests: XCTestCase {
    func testZeroValueFunctionSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected zeroValue<T>() surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropType(_ path: String...) throws -> TypeID {
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) }),
                "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered"
            )
            return sema.types.make(.classType(ClassType(
                classSymbol: symbol,
                args: [],
                nullability: .nonNull
            )))
        }

        let cVariableType = try cinteropType("CVariable")
        let cValueSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValue")])
        )

        let zeroValueFQName = cinteropPkg + [interner.intern("zeroValue")]
        let candidates = sema.symbols.lookupAll(fqName: zeroValueFQName)

        let zeroValue = try XCTUnwrap(candidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.isEmpty
                && signature.typeParameterSymbols.count == 1
        }, "Expected zeroValue<T>() top-level function to be registered")

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: zeroValue))
        let typeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValueSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let flags = try XCTUnwrap(sema.symbols.symbol(zeroValue)?.flags)
        let typeParameterFlags = try XCTUnwrap(sema.symbols.symbol(typeParameter)?.flags)

        XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        XCTAssertEqual(sema.symbols.parentSymbol(for: zeroValue), sema.symbols.lookup(fqName: cinteropPkg))
        XCTAssertEqual(signature.returnType, expectedReturnType)
        XCTAssertEqual(signature.reifiedTypeParameterIndices, [0])
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[cVariableType]])
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [cVariableType])
        XCTAssertTrue(typeParameterFlags.isSuperset(of: [.synthetic, .reifiedTypeParameter]))
    }

    func testZeroValueFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CValue
        import kotlinx.cinterop.zeroValue

        fun makeZeroByte(): CValue<ByteVar> {
            return zeroValue<ByteVar>()
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected zeroValue<ByteVar>() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
