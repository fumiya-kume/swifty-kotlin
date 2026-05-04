@testable import CompilerCore
import XCTest

final class JvmAnnotationSyntheticSurfaceTests: XCTestCase {
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
                "Expected JVM annotation surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJvmDefaultWithCompatibilityAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmDefaultWithCompatibility"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.jvm.JvmDefaultWithCompatibility must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testJvmDefaultWithCompatibilityCarriesClassTarget() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmDefaultWithCompatibility"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "JvmDefaultWithCompatibility must carry @Target metadata"
        )

        XCTAssertEqual(target.arguments, ["AnnotationTarget.CLASS"])
    }

    func testJvmDefaultWithCompatibilityResolvesOnInterfaceAndClass() throws {
        let source = """
        import kotlin.jvm.JvmDefaultWithCompatibility

        @JvmDefaultWithCompatibility
        interface Service {
            fun ping(): String = "ok"
        }

        @JvmDefaultWithCompatibility
        open class BaseService
        """

        _ = try makeSema(source: source)
    }
}
