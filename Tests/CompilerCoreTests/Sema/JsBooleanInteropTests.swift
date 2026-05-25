@testable import CompilerCore
import XCTest

final class JsBooleanInteropTests: XCTestCase {
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
                "Expected JsBoolean interop surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testBooleanToJsBooleanIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsPkg = ["kotlin", "js"].map { interner.intern($0) }
        let jsBooleanSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: jsPkg + [interner.intern("JsBoolean")]
        ))
        let jsBooleanType = try XCTUnwrap(sema.symbols.propertyType(for: jsBooleanSymbol))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsPkg + [interner.intern("toJsBoolean")]).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.receiverType == sema.types.booleanType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == jsBooleanType
            },
            "Boolean.toJsBoolean() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(function))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertEqual(sema.symbols.externalLinkName(for: function), "kk_boolean_toJsBoolean")
    }

    func testBooleanToJsBooleanResolvesFromSource() throws {
        let source = """
        import kotlin.js.JsBoolean
        import kotlin.js.toJsBoolean

        fun convert(value: Boolean): JsBoolean = value.toJsBoolean()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected Boolean.toJsBoolean usage to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let jsBooleanSymbol = try XCTUnwrap(sema.symbols.lookup(
                fqName: ["kotlin", "js", "JsBoolean"].map { ctx.interner.intern($0) }
            ))
            let functionSymbol = try XCTUnwrap(sema.symbols.lookup(
                fqName: [ctx.interner.intern("convert")]
            ))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

            XCTAssertEqual(signature.returnType, sema.symbols.propertyType(for: jsBooleanSymbol))

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toJsBoolean"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_boolean_toJsBoolean")
        }
    }
}
