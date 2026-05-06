@testable import CompilerCore
import Foundation
import XCTest

final class JvmArrayIsArrayOfSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testIsArrayOfSignature() throws {
        let (sema, interner) = try makeSema()

        let arrayFQName = ["kotlin", "Array"].map { interner.intern($0) }
        let arraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: arrayFQName),
            "Expected kotlin.Array to be registered"
        )

        let isArrayOfFQName = ["kotlin", "jvm", "isArrayOf"].map { interner.intern($0) }
        let isArrayOfSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: isArrayOfFQName),
            "Expected kotlin.jvm.isArrayOf to be registered"
        )
        let isArrayOfSignature = try XCTUnwrap(sema.symbols.functionSignature(for: isArrayOfSymbol))
        XCTAssertTrue(sema.symbols.symbol(isArrayOfSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertTrue(sema.symbols.symbol(isArrayOfSymbol)?.flags.contains(.inlineFunction) == true)
        XCTAssertEqual(sema.symbols.externalLinkName(for: isArrayOfSymbol), "kk_array_isArrayOf")

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.star],
            nullability: .nonNull
        )))

        XCTAssertEqual(isArrayOfSignature.receiverType, receiverType)
        XCTAssertEqual(isArrayOfSignature.parameterTypes, [])
        XCTAssertEqual(isArrayOfSignature.returnType, sema.types.booleanType)
        XCTAssertEqual(isArrayOfSignature.typeParameterSymbols.count, 1)
        XCTAssertEqual(isArrayOfSignature.reifiedTypeParameterIndices, [0])
        XCTAssertEqual(isArrayOfSignature.typeParameterUpperBoundsList, [[sema.types.anyType]])
        XCTAssertEqual(isArrayOfSignature.classTypeParameterCount, 0)

        let typeParameterSymbol = try XCTUnwrap(isArrayOfSignature.typeParameterSymbols.first)
        XCTAssertTrue(sema.symbols.symbol(typeParameterSymbol)?.flags.contains(.reifiedTypeParameter) == true)
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameterSymbol), [sema.types.anyType])
    }

    func testIsArrayOfResolvesInSource() throws {
        let source = """
        import kotlin.jvm.isArrayOf

        fun probe(values: Array<*>): Boolean {
            return values.isArrayOf<String>()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let isArrayOfCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "isArrayOf"
            })
            let chosenIsArrayOf = try XCTUnwrap(
                sema.bindings.callBinding(for: isArrayOfCall)?.chosenCallee
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenIsArrayOf),
                "kk_array_isArrayOf"
            )
        }
    }
}
