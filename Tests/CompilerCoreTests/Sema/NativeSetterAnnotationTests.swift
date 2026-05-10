@testable import CompilerCore
import XCTest

final class NativeSetterAnnotationTests: XCTestCase {
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
                "Expected nativeSetter annotation surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testNativeSetterAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "nativeSetter"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.nativeSetter must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testNativeSetterCarriesExpectedMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "nativeSetter"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "nativeSetter must carry @Target metadata"
        )
        let deprecated = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.Deprecated" },
            "nativeSetter must carry Deprecated metadata"
        )

        XCTAssertEqual(Set(target.arguments), Set(["AnnotationTarget.FUNCTION"]))
        XCTAssertEqual(
            deprecated.arguments,
            ["message = \"Use inline extension function with body using dynamic\""]
        )
    }
}
