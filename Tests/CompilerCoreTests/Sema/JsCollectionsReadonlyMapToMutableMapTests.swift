@testable import CompilerCore
import XCTest

final class JsCollectionsReadonlyMapToMutableMapTests: XCTestCase {
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
                "Expected JsReadonlyMap.toMutableMap surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsReadonlyMapToMutableMapIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let pkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
        let readonlyMapSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: pkg + [interner.intern("JsReadonlyMap")]
        ))
        let mutableMapSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: collectionsPkg + [interner.intern("MutableMap")]
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
            classSymbol: mutableMapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(
                fqName: pkg + [interner.intern("JsReadonlyMap"), interner.intern("toMutableMap")]
            ).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == returnType
                    && signature.typeParameterSymbols == [keyTypeParamSymbol, valueTypeParamSymbol]
                    && signature.classTypeParameterCount == 2
            },
            "JsReadonlyMap<K, V>.toMutableMap() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(function))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertEqual(sema.symbols.externalLinkName(for: function), "kk_js_map_toMutableMap")
        XCTAssertTrue(sema.symbols.annotations(for: function).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalJsCollectionsApi"
        })
    }

    func testJsReadonlyMapToMutableMapResolvesFromSource() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalJsCollectionsApi::class)

        import kotlin.js.collections.JsReadonlyMap

        fun scores(map: JsReadonlyMap<String, Int>) = map.toMutableMap()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected JsReadonlyMap.toMutableMap usage to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let functionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [ctx.interner.intern("scores")]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
            let mutableMapSymbol = try XCTUnwrap(sema.symbols.lookup(
                fqName: ["kotlin", "collections", "MutableMap"].map { ctx.interner.intern($0) }
            ))

            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected scores() to return MutableMap<String, Int>")
            }
            XCTAssertEqual(returnClassType.classSymbol, mutableMapSymbol)
            XCTAssertEqual(returnClassType.args.count, 2)

            let keyArg: TypeID
            switch returnClassType.args[0] {
            case let .invariant(arg), let .out(arg):
                keyArg = arg
            case .in, .star:
                return XCTFail("Expected scores() to return MutableMap<String, Int>")
            }
            let valueArg: TypeID
            switch returnClassType.args[1] {
            case let .invariant(arg), let .out(arg):
                valueArg = arg
            case .in, .star:
                return XCTFail("Expected scores() to return MutableMap<String, Int>")
            }

            XCTAssertEqual(keyArg, sema.types.stringType)
            XCTAssertEqual(valueArg, sema.types.intType)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toMutableMap"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_js_map_toMutableMap")
        }
    }
}
