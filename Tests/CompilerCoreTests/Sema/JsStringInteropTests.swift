@testable import CompilerCore
import XCTest

final class JsStringInteropTests: XCTestCase {
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
                "Expected JsString interop surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testToJsStringIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsPkg = ["kotlin", "js"].map { interner.intern($0) }
        let jsStringSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: jsPkg + [interner.intern("JsString")]
        ))
        let jsStringType = try XCTUnwrap(sema.symbols.propertyType(for: jsStringSymbol))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsPkg + [interner.intern("toJsString")]).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == jsStringType
            },
            "String.toJsString() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(function))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.externalLinkName(for: function), "kk_string_toJsString")
        XCTAssertTrue(sema.symbols.annotations(for: function).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalWasmJsInterop"
        })
    }

    func testJsStringSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsPkg = ["kotlin", "js"].map { interner.intern($0) }
        let jsStringSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: jsPkg + [interner.intern("JsString")]
        ))
        let jsAnySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: jsPkg + [interner.intern("JsAny")]
        ))
        let info = try XCTUnwrap(sema.symbols.symbol(jsStringSymbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.openType))
        XCTAssertEqual(sema.symbols.directSupertypes(for: jsStringSymbol), [jsAnySymbol])
        XCTAssertTrue(sema.symbols.annotations(for: jsStringSymbol).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalWasmJsInterop"
        })
    }

    func testToJsStringResolvesFromSource() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalWasmJsInterop::class)

        import kotlin.js.JsString
        import kotlin.js.toJsString

        fun convert(value: String): JsString = value.toJsString()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected String.toJsString usage to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let jsStringSymbol = try XCTUnwrap(sema.symbols.lookup(
                fqName: ["kotlin", "js", "JsString"].map { ctx.interner.intern($0) }
            ))
            let functionSymbol = try XCTUnwrap(sema.symbols.lookup(
                fqName: [ctx.interner.intern("convert")]
            ))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
            guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("Expected convert() to return JsString")
            }

            XCTAssertEqual(returnClassType.classSymbol, jsStringSymbol)
            XCTAssertEqual(returnClassType.args, [])

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toJsString"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_string_toJsString")
        }
    }
}
