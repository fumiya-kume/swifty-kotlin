@testable import CompilerCore
import XCTest

final class JsNumberExternalClassTests: XCTestCase {
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
                "Expected JsNumber external class surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsNumberClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsNumber"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsNumber must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertNotNil(sema.symbols.propertyType(for: symbol))
    }

    func testJsNumberToDoubleIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsNumberFQName = ["kotlin", "js", "JsNumber"].map { interner.intern($0) }
        let jsNumberSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: jsNumberFQName))
        let receiverType = try XCTUnwrap(sema.symbols.propertyType(for: jsNumberSymbol))

        let toDouble = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsNumberFQName + [interner.intern("toDouble")]).first { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == sema.types.doubleType
            },
            "JsNumber.toDouble() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(toDouble))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: toDouble))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertEqual(sema.symbols.externalLinkName(for: toDouble), "kk_js_number_toDouble")
    }

    func testJsNumberToIntIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsNumberFQName = ["kotlin", "js", "JsNumber"].map { interner.intern($0) }
        let jsNumberSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: jsNumberFQName))
        let receiverType = try XCTUnwrap(sema.symbols.propertyType(for: jsNumberSymbol))

        let toInt = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsNumberFQName + [interner.intern("toInt")]).first { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.receiverType == receiverType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == sema.types.intType
            },
            "JsNumber.toInt() must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(toInt))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: toInt))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
        XCTAssertEqual(signature.valueParameterIsVararg, [])
        XCTAssertEqual(sema.symbols.externalLinkName(for: toInt), "kk_js_number_toInt")
    }

    func testJsNumberToDoubleResolvesFromSource() throws {
        let source = """
        import kotlin.js.JsNumber

        fun primitive(value: JsNumber): Double = value.toDouble()
        """
        let (sema, interner) = try makeSema(source: source)
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("primitive")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))

        XCTAssertEqual(signature.returnType, sema.types.doubleType)
    }

    func testJsNumberToIntResolvesFromSource() throws {
        let source = """
        import kotlin.js.JsNumber

        fun primitive(value: JsNumber): Int = value.toInt()
        """
        let (sema, interner) = try makeSema(source: source)
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("primitive")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))

        XCTAssertEqual(signature.returnType, sema.types.intType)
    }
}
