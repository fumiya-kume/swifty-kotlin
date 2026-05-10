@testable import CompilerCore
import XCTest

final class JsPromiseExternalClassTests: XCTestCase {
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
                "Expected Promise external class surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testPromiseClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "Promise"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.Promise must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.openType))
    }

    func testPromiseDeclaresCovariantTypeParameter() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "Promise"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let typeParams = sema.types.nominalTypeParameterSymbols(for: symbol)

        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: symbol), [.out])

        let typeParam = try XCTUnwrap(sema.symbols.symbol(typeParams[0]))
        XCTAssertEqual(typeParam.kind, .typeParameter)
        XCTAssertEqual(typeParam.name, interner.intern("T"))
    }
}
