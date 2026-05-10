@testable import CompilerCore
import Foundation
import XCTest

final class JsNonModuleAnnotationTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx
    }

    func testJsNonModuleAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsNonModule"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsNonModule must be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testJsNonModuleCarriesTargetMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsNonModule"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)
        let target = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "JsNonModule must carry @Target metadata"
        )

        XCTAssertEqual(
            Set(target.arguments),
            Set([
                "AnnotationTarget.CLASS",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.FILE",
            ])
        )
    }

    func testJsNonModuleIsAcceptedOnClassFunctionAndProperty() {
        let source = """
        import kotlin.js.JsNonModule

        @JsNonModule
        class JQuery

        @JsNonModule
        fun makeJQuery(): JQuery = JQuery()

        @JsNonModule
        val jqueryName: String = "jquery"
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(
            errors.isEmpty,
            "Expected JsNonModule to type-check on class/function/property targets, got \(errors)"
        )
    }
}
