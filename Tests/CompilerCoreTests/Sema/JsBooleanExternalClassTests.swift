@testable import CompilerCore
import XCTest

final class JsBooleanExternalClassTests: XCTestCase {
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
                "Expected JsBoolean external class surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsBooleanClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsBoolean"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsBoolean must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertNotNil(sema.symbols.propertyType(for: symbol))
    }

    func testJsBooleanToBooleanIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsBooleanFQName = ["kotlin", "js", "JsBoolean"].map { interner.intern($0) }
        let jsBooleanSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: jsBooleanFQName))
        let receiverType = try XCTUnwrap(sema.symbols.propertyType(for: jsBooleanSymbol))

        let toBoolean = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsBooleanFQName + [interner.intern("toBoolean")]).first { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == sema.types.booleanType
            },
            "JsBoolean.toBoolean() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(toBoolean))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: toBoolean))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertEqual(sema.symbols.externalLinkName(for: toBoolean), "kk_js_boolean_toBoolean")
    }

    func testJsBooleanToBooleanResolvesFromSource() throws {
        let source = """
        import kotlin.js.JsBoolean

        fun primitive(value: JsBoolean): Boolean = value.toBoolean()
        """
        let (sema, interner) = try makeSema(source: source)
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("primitive")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))

        XCTAssertEqual(signature.returnType, sema.types.booleanType)
    }
}
