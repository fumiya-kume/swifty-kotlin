@testable import CompilerCore
import XCTest

final class JsReferenceInteropTests: XCTestCase {
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
                "Expected JsReference interop surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testToJsReferenceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsPkg = ["kotlin", "js"].map { interner.intern($0) }
        let jsReferenceSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: jsPkg + [interner.intern("JsReference")]
        ))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsPkg + [interner.intern("toJsReference")]).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol),
                      let typeParamSymbol = signature.typeParameterSymbols.first
                else {
                    return false
                }
                let typeParamType = sema.types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbol,
                    nullability: .nonNull
                )))
                let returnType = sema.types.make(.classType(ClassType(
                    classSymbol: jsReferenceSymbol,
                    args: [.invariant(typeParamType)],
                    nullability: .nonNull
                )))
                return signature.receiverType == typeParamType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == returnType
                    && signature.typeParameterUpperBoundsList == [[sema.types.anyType]]
            },
            "T.toJsReference() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(function))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: jsReferenceSymbol), [.invariant])
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertEqual(sema.symbols.externalLinkName(for: function), "kk_toJsReference")
    }

    func testToJsReferenceResolvesFromSource() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalWasmJsInterop::class)

        import kotlin.js.JsReference
        import kotlin.js.toJsReference

        fun convert(value: String): JsReference<String> = value.toJsReference()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected T.toJsReference usage to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let jsReferenceSymbol = try XCTUnwrap(sema.symbols.lookup(
                fqName: ["kotlin", "js", "JsReference"].map { ctx.interner.intern($0) }
            ))
            let functionSymbol = try XCTUnwrap(sema.symbols.lookup(
                fqName: [ctx.interner.intern("convert")]
            ))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected convert() to return JsReference<String>")
            }

            XCTAssertEqual(returnClassType.classSymbol, jsReferenceSymbol)
            let returnArg: TypeID
            switch try XCTUnwrap(returnClassType.args.first) {
            case let .invariant(arg), let .out(arg):
                returnArg = arg
            case .in, .star:
                return XCTFail("Expected convert() to return JsReference<String>")
            }
            XCTAssertEqual(returnArg, sema.types.stringType)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toJsReference"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_toJsReference")
        }
    }
}
