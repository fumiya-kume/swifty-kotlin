@testable import CompilerCore
import XCTest

final class NativeCInteropCValueUseContentsFunctionTests: XCTestCase {
    func testUseContentsSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected useContents surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let useContentsFQName = cinteropPkg + [interner.intern("useContents")]
        let candidates = sema.symbols.lookupAll(fqName: useContentsFQName)
        let useContents = try XCTUnwrap(candidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType != nil
                && signature.parameterTypes.count == 1
                && signature.typeParameterSymbols.count == 2
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: useContents))
        let tTypeParameter = try XCTUnwrap(signature.typeParameterSymbols.first)
        let rTypeParameter = try XCTUnwrap(signature.typeParameterSymbols.last)
        let tTypeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: tTypeParameter,
            nullability: .nonNull
        )))
        let rTypeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: rTypeParameter,
            nullability: .nonNull
        )))
        let flags = try XCTUnwrap(sema.symbols.symbol(useContents)?.flags)

        let cVariableSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CVariable")]),
            "kotlinx.cinterop.CVariable must be registered"
        )
        let cVariableType = sema.types.make(.classType(ClassType(
            classSymbol: cVariableSymbol,
            args: [],
            nullability: .nonNull
        )))
        let cValueSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValue")]),
            "kotlinx.cinterop.CValue must be registered"
        )
        let expectedReceiverType = sema.types.make(.classType(ClassType(
            classSymbol: cValueSymbol,
            args: [.invariant(tTypeParameterType)],
            nullability: .nonNull
        )))
        let expectedBlockType = sema.types.make(.functionType(FunctionType(
            receiver: tTypeParameterType,
            params: [],
            returnType: rTypeParameterType
        )))

        XCTAssertTrue(flags.isSuperset(of: [.synthetic, .inlineFunction]))
        XCTAssertEqual(sema.symbols.parentSymbol(for: useContents), sema.symbols.lookup(fqName: cinteropPkg))
        XCTAssertEqual(signature.receiverType, expectedReceiverType)
        XCTAssertEqual(signature.parameterTypes, [expectedBlockType])
        XCTAssertEqual(signature.returnType, rTypeParameterType)
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[cVariableType], [sema.types.anyType]])
        XCTAssertEqual(signature.reifiedTypeParameterIndices, [])
    }

    func testUseContentsResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValue
        import kotlinx.cinterop.CVariable
        import kotlinx.cinterop.useContents

        abstract class MyVar : CVariable
        abstract class MyStruct : CVariable {
            var x: Int = 0
        }

        fun readX(value: CValue<MyStruct>): Int {
            return value.useContents { x }
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected useContents to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
