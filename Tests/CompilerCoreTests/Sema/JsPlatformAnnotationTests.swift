@testable import CompilerCore
import Foundation
import XCTest

final class JsPlatformAnnotationTests: XCTestCase {
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

    func testEagerInitializationAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "EagerInitialization"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.EagerInitialization must be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testEagerInitializationCarriesStdlibMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "EagerInitialization"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)
        let target = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "EagerInitialization must carry @Target metadata"
        )
        let retention = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "EagerInitialization must carry @Retention metadata"
        )
        let deprecated = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.Deprecated" },
            "EagerInitialization must carry @Deprecated metadata"
        )

        XCTAssertEqual(Set(target.arguments), Set(["AnnotationTarget.PROPERTY"]))
        XCTAssertEqual(retention.arguments, ["AnnotationRetention.BINARY"])
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.ExperimentalStdlibApi" },
            "EagerInitialization must carry @ExperimentalStdlibApi metadata"
        )
        XCTAssertTrue(
            deprecated.arguments.contains { $0.contains("temporal migration assistance") },
            "EagerInitialization deprecation message should mention temporary migration assistance"
        )
    }

    func testEagerInitializationIsAcceptedOnPropertyWithStdlibOptIn() {
        let source = """
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
        import kotlin.js.EagerInitialization

        @EagerInitialization
        val eagerValue: Int = 1
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(
            errors.isEmpty,
            "Expected EagerInitialization on a property to type-check with ExperimentalStdlibApi opt-in, got \(errors)"
        )
    }
}
