@testable import CompilerCore
import Foundation
import XCTest

final class JsExternalInheritorsOnlyAnnotationTests: XCTestCase {
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

    func testJsExternalInheritorsOnlyAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsExternalInheritorsOnly"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsExternalInheritorsOnly must be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testJsExternalInheritorsOnlyCarriesStdlibMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsExternalInheritorsOnly"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)
        let target = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "JsExternalInheritorsOnly must carry @Target metadata"
        )

        XCTAssertEqual(Set(target.arguments), Set(["AnnotationTarget.CLASS"]))
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.ExperimentalStdlibApi" },
            "JsExternalInheritorsOnly must carry @ExperimentalStdlibApi metadata"
        )
    }

    func testJsExternalInheritorsOnlyIsAcceptedOnClassWithStdlibOptIn() {
        let source = """
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
        import kotlin.js.JsExternalInheritorsOnly

        @JsExternalInheritorsOnly
        class Props
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(
            errors.isEmpty,
            "Expected JsExternalInheritorsOnly on a class to type-check with ExperimentalStdlibApi opt-in, got \(errors)"
        )
    }
}
