@testable import CompilerCore
import XCTest

final class JsDefinedExternallyPropertyTests: XCTestCase {
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
                "Expected definedExternally synthetic property surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testDefinedExternallyPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let fqName = packageFQName + [interner.intern("definedExternally")]
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.definedExternally must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .property)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.propertyType(for: symbol), sema.types.nothingType)
        XCTAssertNil(sema.symbols.externalLinkName(for: symbol))
    }

    func testDefinedExternallyPropertyParentIsKotlinJsPackage() throws {
        let (sema, interner) = try makeSema()
        let packageFQName = ["kotlin", "js"].map { interner.intern($0) }
        let packageSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: packageFQName))
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: packageFQName + [interner.intern("definedExternally")])
        )

        XCTAssertEqual(sema.symbols.parentSymbol(for: propertySymbol), packageSymbol)
    }
}
