@testable import CompilerCore
import XCTest

final class JsExternalArgumentAnnotationTests: XCTestCase {
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
                "Expected JsExternalArgument annotation surface to resolve cleanly, got: \(diagnostics)"
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

    func testJsExternalArgumentAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsExternalArgument"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsExternalArgument must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testJsExternalArgumentCarriesStdlibOptInAndValueParameterTarget() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsExternalArgument"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)
        let target = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "JsExternalArgument must carry @Target metadata"
        )
        let retention = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "JsExternalArgument must carry @Retention metadata"
        )

        XCTAssertEqual(target.arguments, ["AnnotationTarget.VALUE_PARAMETER"])
        XCTAssertEqual(retention.arguments, ["AnnotationRetention.BINARY"])
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.ExperimentalStdlibApi" },
            "JsExternalArgument must carry @ExperimentalStdlibApi metadata"
        )
    }

    func testJsExternalArgumentIsAcceptedOnValueParameterWithStdlibOptIn() {
        let source = """
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
        import kotlin.js.JsExternalArgument

        fun accept(@JsExternalArgument value: String) {}
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(
            errors.isEmpty,
            "Expected JsExternalArgument on a value parameter to type-check with ExperimentalStdlibApi opt-in, got \(errors)"
        )
    }
}
