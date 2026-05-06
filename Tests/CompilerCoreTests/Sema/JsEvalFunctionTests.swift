@testable import CompilerCore
import XCTest

final class JsEvalFunctionTests: XCTestCase {
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
                "Expected eval synthetic function surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testEvalFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            evalSymbol(
                in: packageFQName,
                sema: sema,
                interner: interner
            ),
            "kotlin.js.eval(String) must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))

        XCTAssertEqual(info.kind, .function)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: symbol), sema.symbols.lookup(fqName: packageFQName))
        XCTAssertNil(sema.symbols.externalLinkName(for: symbol))
        XCTAssertEqual(signature.parameterTypes, [sema.types.stringType])
        XCTAssertEqual(signature.returnType, sema.types.anyType)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(signature.valueParameterIsVararg, [false])
    }

    func testEvalParameterIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            evalSymbol(
                in: packageFQName,
                sema: sema,
                interner: interner
            )
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        let parameter = try XCTUnwrap(signature.valueParameterSymbols.first)

        XCTAssertEqual(sema.symbols.symbol(parameter)?.name, interner.intern("expr"))
        XCTAssertEqual(sema.symbols.propertyType(for: parameter), sema.types.stringType)
        XCTAssertEqual(sema.symbols.parentSymbol(for: parameter), symbol)
    }

    private func evalSymbol(
        in packageFQName: [InternedString],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = packageFQName + [interner.intern("eval")]
        return sema.symbols.lookupAll(fqName: fqName).first { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.parameterTypes == [
                sema.types.stringType,
            ]
        }
    }
}
