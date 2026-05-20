@testable import CompilerCore
import XCTest

final class JsArrayToListTests: XCTestCase {
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
                "Expected JsArray.toList surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsArrayToListIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsPkg = ["kotlin", "js"].map { interner.intern($0) }
        let collectionsPkg = ["kotlin", "collections"].map { interner.intern($0) }
        let jsArraySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: jsPkg + [interner.intern("JsArray")]
        ))
        let listSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: collectionsPkg + [interner.intern("List")]
        ))
        let typeParamSymbol = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: jsArraySymbol).first)
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: jsArraySymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(typeParamType)],
            nullability: .nonNull
        )))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsPkg + [interner.intern("JsArray"), interner.intern("toList")]).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == returnType
                    && signature.typeParameterSymbols == [typeParamSymbol]
                    && signature.classTypeParameterCount == 1
            },
            "JsArray<T>.toList() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(function))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[sema.types.nullableAnyType]])
        XCTAssertEqual(sema.symbols.externalLinkName(for: function), "kk_js_array_toList")
        XCTAssertTrue(sema.symbols.annotations(for: function).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalWasmJsInterop"
        })
    }

    func testJsArrayToListResolvesFromSource() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalWasmJsInterop::class)

        import kotlin.js.JsArray

        fun strings(array: JsArray<String>) = array.toList()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected JsArray.toList usage to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let functionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [ctx.interner.intern("strings")]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
            let listSymbol = try XCTUnwrap(sema.symbols.lookup(
                fqName: ["kotlin", "collections", "List"].map { ctx.interner.intern($0) }
            ))

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

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toList"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_js_array_toList")
        }
    }
}
