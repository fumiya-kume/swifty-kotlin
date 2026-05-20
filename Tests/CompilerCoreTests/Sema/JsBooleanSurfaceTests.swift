@testable import CompilerCore
import XCTest

final class JsBooleanSurfaceTests: XCTestCase {
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
                "Expected JsBoolean surface to resolve cleanly, got: \(diagnostics)"
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

    func testJsBooleanClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let jsBooleanFQName = ["kotlin", "js", "JsBoolean"].map { interner.intern($0) }
        let jsBooleanSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: jsBooleanFQName),
            "kotlin.js.JsBoolean must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(jsBooleanSymbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertNotNil(sema.symbols.propertyType(for: jsBooleanSymbol))
        XCTAssertEqual(
            sema.symbols.parentSymbol(for: jsBooleanSymbol),
            sema.symbols.lookup(fqName: ["kotlin", "js"].map { interner.intern($0) })
        )
    }

    func testJsBooleanExtendsJsAny() throws {
        let (sema, interner) = try makeSema()
        let jsBooleanSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "js", "JsBoolean"].map { interner.intern($0) })
        )
        let jsAnySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "js", "JsAny"].map { interner.intern($0) })
        )

        XCTAssertEqual(sema.symbols.directSupertypes(for: jsBooleanSymbol), [jsAnySymbol])
    }

    func testJsBooleanCanBeImportedAndUsedAsParameterType() {
        let source = """
        import kotlin.js.JsBoolean

        fun accept(value: JsBoolean): JsBoolean = value
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(errors.isEmpty, "Expected JsBoolean parameter usage to type-check, got \(errors)")
    }
}
