@testable import CompilerCore
import XCTest

final class JsNumberSurfaceTests: XCTestCase {
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
                "Expected JsNumber surface to resolve cleanly, got: \(diagnostics)"
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
        XCTAssertEqual(
            sema.symbols.parentSymbol(for: symbol),
            sema.symbols.lookup(fqName: ["kotlin", "js"].map { interner.intern($0) })
        )
        XCTAssertNotNil(sema.symbols.propertyType(for: symbol))
    }

    func testJsNumberExtendsJsAny() throws {
        let (sema, interner) = try makeSema()
        let jsNumberSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "js", "JsNumber"].map { interner.intern($0) })
        )
        let jsAnySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "js", "JsAny"].map { interner.intern($0) })
        )

        XCTAssertEqual(sema.symbols.directSupertypes(for: jsNumberSymbol), [jsAnySymbol])
    }

    func testJsNumberCanBeImportedAndUsedAsParameterType() {
        let source = """
        import kotlin.js.JsNumber

        fun accept(value: JsNumber): JsNumber = value
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(errors.isEmpty, "Expected JsNumber parameter usage to type-check, got \(errors)")
    }
}
