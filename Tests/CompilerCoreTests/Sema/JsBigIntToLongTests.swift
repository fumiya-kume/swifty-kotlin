@testable import CompilerCore
import XCTest

final class JsBigIntToLongTests: XCTestCase {
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
                "Expected JsBigInt.toLong surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsBigIntToLongIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsPkg = ["kotlin", "js"].map { interner.intern($0) }
        let jsBigIntSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: jsPkg + [interner.intern("JsBigInt")]
        ))
        let receiverType = try XCTUnwrap(sema.symbols.propertyType(for: jsBigIntSymbol))
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsPkg + [interner.intern("JsBigInt"), interner.intern("toLong")]).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == sema.types.longType
            },
            "JsBigInt.toLong() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(function))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertEqual(sema.symbols.externalLinkName(for: function), "kk_js_bigint_toLong")
        XCTAssertTrue(sema.symbols.annotations(for: function).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalWasmJsInterop"
        })
    }

    func testJsBigIntSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsPkg = ["kotlin", "js"].map { interner.intern($0) }
        let jsBigIntSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: jsPkg + [interner.intern("JsBigInt")]
        ))
        let jsAnySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: jsPkg + [interner.intern("JsAny")]
        ))
        let info = try XCTUnwrap(sema.symbols.symbol(jsBigIntSymbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.openType))
        XCTAssertEqual(sema.symbols.directSupertypes(for: jsBigIntSymbol), [jsAnySymbol])
        XCTAssertTrue(sema.symbols.annotations(for: jsBigIntSymbol).contains {
            $0.annotationFQName == "kotlin.js.ExperimentalWasmJsInterop"
        })
    }

    func testJsBigIntToLongResolvesFromSource() throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalWasmJsInterop::class)

        import kotlin.js.JsBigInt

        fun convert(value: JsBigInt): Long = value.toLong()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected JsBigInt.toLong usage to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let functionSymbol = try XCTUnwrap(sema.symbols.lookup(
                fqName: [ctx.interner.intern("convert")]
            ))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
            XCTAssertEqual(signature.returnType, sema.types.longType)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toLong"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), "kk_js_bigint_toLong")
        }
    }
}
