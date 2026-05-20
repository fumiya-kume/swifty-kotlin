@testable import CompilerCore
import XCTest

final class JsCollectionsReadonlyMapToMapTests: XCTestCase {
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
                "Expected JsReadonlyMap.toMap surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsReadonlyMapToMapIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
        let readonlyMapSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsReadonlyMap")]
        ))
        let mapSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: collectionsPkg + [interner.intern("Map")]
        ))
        let typeParamSymbols = sema.types.nominalTypeParameterSymbols(for: readonlyMapSymbol)
        XCTAssertEqual(typeParamSymbols.count, 2)
        let keyTypeParamSymbol = typeParamSymbols[0]
        let valueTypeParamSymbol = typeParamSymbols[1]
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: readonlyMapSymbol), [.invariant, .out])

        let keyType = sema.types.make(.typeParam(TypeParamType(
            symbol: keyTypeParamSymbol,
            nullability: .nonNull
        )))
        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: valueTypeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: readonlyMapSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: pkg + [interner.intern("JsReadonlyMap"), interner.intern("toMap")]).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == returnType
                    && signature.typeParameterSymbols == [keyTypeParamSymbol, valueTypeParamSymbol]
                    && signature.classTypeParameterCount == 2
            },
            "JsReadonlyMap<K, V>.toMap() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(function))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertEqual(sema.symbols.externalLinkName(for: function), "kk_js_map_toMap")
        XCTAssertTrue(sema.symbols.annotations(for: function).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalJsCollectionsApi"
        })
    }

    func testJsReadonlyMapToMapResolvesFromSource() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalJsCollectionsApi::class)

        import kotlin.js.collections.JsReadonlyMap

        fun scores(map: JsReadonlyMap<String, Int>) = map.toMap()
        """
        let (sema, interner) = try makeSema(source: source)
        let mapSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: ["kotlin", "collections", "Map"].map { interner.intern($0) }
        ))
        let functionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("scores")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Expected scores() to return Map<String, Int>")
        }
        XCTAssertEqual(returnClassType.classSymbol, mapSymbol)
        XCTAssertEqual(returnClassType.args.count, 2)

        let keyArg: TypeID
        switch returnClassType.args[0] {
        case let .invariant(arg), let .out(arg):
            keyArg = arg
        case .in, .star:
            return XCTFail("Expected scores() to return Map<String, Int>")
        }
        let valueArg: TypeID
        switch returnClassType.args[1] {
        case let .invariant(arg), let .out(arg):
            valueArg = arg
        case .in, .star:
            return XCTFail("Expected scores() to return Map<String, Int>")
        }

        XCTAssertEqual(keyArg, sema.types.stringType)
        XCTAssertEqual(valueArg, sema.types.intType)
    }
}
