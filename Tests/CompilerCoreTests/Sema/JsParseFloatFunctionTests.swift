@testable import CompilerCore
import XCTest

final class JsParseFloatFunctionTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected parseFloat synthetic function surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testParseFloatFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            parseFloatSymbol(
                in: packageFQName,
                sema: sema,
                interner: interner
            ),
            "kotlin.js.parseFloat(String, Int) must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))

        XCTAssertEqual(info.kind, .function)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: symbol), sema.symbols.lookup(fqName: packageFQName))
        XCTAssertNil(sema.symbols.externalLinkName(for: symbol))
        XCTAssertEqual(signature.parameterTypes, [sema.types.stringType, sema.types.intType])
        XCTAssertEqual(signature.returnType, sema.types.doubleType)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, true])
        XCTAssertEqual(signature.valueParameterIsVararg, [false, false])
    }

    func testParseFloatParametersAndDeprecatedMetadataAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            parseFloatSymbol(
                in: packageFQName,
                sema: sema,
                interner: interner
            )
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        let sParameter = try XCTUnwrap(signature.valueParameterSymbols.first)
        let radixParameter = try XCTUnwrap(signature.valueParameterSymbols.dropFirst().first)
        let deprecated = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.Deprecated" }
        )

        XCTAssertEqual(sema.symbols.symbol(sParameter)?.name, interner.intern("s"))
        XCTAssertEqual(sema.symbols.propertyType(for: sParameter), sema.types.stringType)
        XCTAssertEqual(sema.symbols.symbol(radixParameter)?.name, interner.intern("radix"))
        XCTAssertEqual(sema.symbols.propertyType(for: radixParameter), sema.types.intType)
        XCTAssertEqual(sema.symbols.parentSymbol(for: sParameter), symbol)
        XCTAssertEqual(sema.symbols.parentSymbol(for: radixParameter), symbol)
        XCTAssertTrue(deprecated.arguments.contains("message = \"Use toDouble() instead.\""))
        XCTAssertTrue(deprecated.arguments.contains("replaceWith = ReplaceWith(\"s.toDouble()\")"))
        XCTAssertTrue(deprecated.arguments.contains("level = DeprecationLevel.ERROR"))
    }

    private func parseFloatSymbol(
        in packageFQName: [InternedString],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = packageFQName + [interner.intern("parseFloat")]
        return sema.symbols.lookupAll(fqName: fqName).first { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.parameterTypes == [
                sema.types.stringType,
                sema.types.intType,
            ]
        }
    }
}
