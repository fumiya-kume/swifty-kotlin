@testable import CompilerCore
import XCTest

final class JsJsonFunctionTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsonInterfaceAndFactoryFunctionAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let kotlinJsFQName = ["kotlin", "js"].map { interner.intern($0) }
        let kotlinJsPackage = try XCTUnwrap(
            sema.symbols.lookup(fqName: kotlinJsFQName),
            "Expected kotlin.js package to be registered"
        )

        let jsonFQName = kotlinJsFQName + [interner.intern("Json")]
        let jsonSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: jsonFQName),
            "Expected kotlin.js.Json to be registered"
        )
        let jsonInfo = try XCTUnwrap(sema.symbols.symbol(jsonSymbol))
        XCTAssertEqual(jsonInfo.kind, .interface)
        XCTAssertEqual(jsonInfo.visibility, .public)
        XCTAssertTrue(jsonInfo.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: jsonSymbol), kotlinJsPackage)

        let jsonType = sema.types.make(.classType(ClassType(
            classSymbol: jsonSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: jsonSymbol), jsonType)

        let pairFQName = [interner.intern("kotlin"), interner.intern("Pair")]
        let pairSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: pairFQName),
            "Expected kotlin.Pair to be available for json(vararg pairs)"
        )
        let pairStringNullableAnyType = sema.types.make(.classType(ClassType(
            classSymbol: pairSymbol,
            args: [
                .out(sema.types.stringType),
                .out(sema.types.nullableAnyType),
            ],
            nullability: .nonNull
        )))

        let jsonFunctionFQName = kotlinJsFQName + [interner.intern("json")]
        let jsonFunctionSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsonFunctionFQName).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.parameterTypes == [pairStringNullableAnyType]
                    && signature.returnType == jsonType
                    && signature.valueParameterIsVararg == [true]
            },
            "Expected kotlin.js.json(vararg pairs: Pair<String, Any?>): Json"
        )
        let jsonFunctionInfo = try XCTUnwrap(sema.symbols.symbol(jsonFunctionSymbol))
        XCTAssertEqual(jsonFunctionInfo.kind, .function)
        XCTAssertEqual(jsonFunctionInfo.visibility, .public)
        XCTAssertTrue(jsonFunctionInfo.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: jsonFunctionSymbol), kotlinJsPackage)
        XCTAssertNil(sema.symbols.externalLinkName(for: jsonFunctionSymbol))

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: jsonFunctionSymbol))
        XCTAssertEqual(signature.parameterTypes, [pairStringNullableAnyType])
        XCTAssertEqual(signature.returnType, jsonType)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(signature.valueParameterIsVararg, [true])

        let pairsParameter = try XCTUnwrap(signature.valueParameterSymbols.first)
        XCTAssertEqual(sema.symbols.symbol(pairsParameter)?.name, interner.intern("pairs"))
        XCTAssertEqual(sema.symbols.parentSymbol(for: pairsParameter), jsonFunctionSymbol)
        XCTAssertEqual(sema.symbols.propertyType(for: pairsParameter), pairStringNullableAnyType)
    }
}
