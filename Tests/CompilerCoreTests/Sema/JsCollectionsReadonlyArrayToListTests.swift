@testable import CompilerCore
import XCTest

final class JsCollectionsReadonlyArrayToListTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected JsReadonlyArray.toList surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsReadonlyArrayToListIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
        let readonlyArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsReadonlyArray")]
        ))
        let listSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: collectionsPkg + [interner.intern("List")]
        ))
        let typeParamSymbol = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: readonlyArraySymbol).first)
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: readonlyArraySymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: pkg + [interner.intern("JsReadonlyArray"), interner.intern("toList")]).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == returnType
                    && signature.typeParameterSymbols == [typeParamSymbol]
                    && signature.classTypeParameterCount == 1
            },
            "JsReadonlyArray<E>.toList() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(function))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertEqual(sema.symbols.externalLinkName(for: function), "kk_js_array_toList")
        XCTAssertTrue(sema.symbols.annotations(for: function).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalJsCollectionsApi"
        })
    }

    func testJsReadonlyArrayToListResolvesFromSource() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalJsCollectionsApi::class)

        import kotlin.js.collections.JsReadonlyArray

        fun strings(array: JsReadonlyArray<String>) = array.toList()
        """
        let (sema, interner) = try makeSema(source: source)
        let listSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: ["kotlin", "collections", "List"].map { interner.intern($0) }
        ))
        let functionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("strings")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Expected strings() to return List<String>")
        }
        XCTAssertEqual(returnClassType.classSymbol, listSymbol)
        let returnArg: TypeID
        switch try XCTUnwrap(returnClassType.args.first) {
        case let .invariant(arg), let .out(arg):
            returnArg = arg
        case .in, .star:
            return XCTFail("Expected strings() to return List<String>")
        }
        XCTAssertEqual(returnArg, sema.types.stringType)
    }
}
