@testable import CompilerCore
import XCTest

final class JsStringSurfaceTests: XCTestCase {
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
                "Expected JsString surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are asserted by each test.
        }
        return ctx
    }

    func testJsStringClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsString"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsString must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(
            sema.symbols.parentSymbol(for: symbol),
            sema.symbols.lookup(fqName: ["kotlin", "js"].map { interner.intern($0) })
        )
        XCTAssertNotNil(sema.symbols.propertyType(for: symbol))
    }

    func testJsStringExtendsJsAny() throws {
        let (sema, interner) = try makeSema()
        let jsStringSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "js", "JsString"].map { interner.intern($0) })
        )
        let jsAnySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "js", "JsAny"].map { interner.intern($0) })
        )

        XCTAssertEqual(sema.symbols.directSupertypes(for: jsStringSymbol), [jsAnySymbol])
    }

    func testJsStringCanBeImportedAndUsedAsParameterType() {
        let source = """
        import kotlin.js.JsString

        fun accept(value: JsString): JsString = value
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(errors.isEmpty, "Expected JsString parameter usage to type-check, got \(errors)")
    }
}
