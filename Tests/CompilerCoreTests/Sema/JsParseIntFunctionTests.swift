@testable import CompilerCore
import XCTest

final class JsParseIntFunctionTests: XCTestCase {
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
                "Expected parseInt synthetic function surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testParseIntStringFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            parseIntSymbol(
                in: packageFQName,
                sema: sema,
                interner: interner
            ),
            "kotlin.js.parseInt(String) must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))

        XCTAssertEqual(info.kind, .function)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: symbol), sema.symbols.lookup(fqName: packageFQName))
        XCTAssertNil(sema.symbols.externalLinkName(for: symbol))
        XCTAssertEqual(signature.parameterTypes, [sema.types.stringType])
        XCTAssertEqual(signature.returnType, sema.types.intType)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(signature.valueParameterIsVararg, [false])
    }

    func testParseIntStringParameterAndDeprecatedMetadataAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            parseIntSymbol(
                in: packageFQName,
                sema: sema,
                interner: interner
            )
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        let parameter = try XCTUnwrap(signature.valueParameterSymbols.first)
        let parameterInfo = try XCTUnwrap(sema.symbols.symbol(parameter))
        let deprecated = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.Deprecated" }
        )

        XCTAssertEqual(parameterInfo.kind, .valueParameter)
        XCTAssertEqual(parameterInfo.name, interner.intern("s"))
        XCTAssertEqual(sema.symbols.parentSymbol(for: parameter), symbol)
        XCTAssertEqual(sema.symbols.propertyType(for: parameter), sema.types.stringType)
        XCTAssertTrue(deprecated.arguments.contains("message = \"Use toInt() instead.\""))
        XCTAssertTrue(deprecated.arguments.contains("replaceWith = ReplaceWith(\"s.toInt()\")"))
        XCTAssertTrue(deprecated.arguments.contains("level = DeprecationLevel.ERROR"))
    }

    private func parseIntSymbol(
        in packageFQName: [InternedString],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = packageFQName + [interner.intern("parseInt")]
        return sema.symbols.lookupAll(fqName: fqName).first { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.parameterTypes == [sema.types.stringType]
        }
    }
}
