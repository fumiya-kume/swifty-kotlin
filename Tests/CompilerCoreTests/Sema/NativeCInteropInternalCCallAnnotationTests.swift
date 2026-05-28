@testable import CompilerCore
import Foundation
import XCTest

final class NativeCInteropInternalCCallAnnotationTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected CCall surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func cCallSymbol(sema: SemaModule, interner: StringInterner) throws -> SymbolID {
        try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "internal", "CCall"].map { interner.intern($0) }),
            "kotlinx.cinterop.internal.CCall must be registered"
        )
    }

    func testCCallAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cCallSymbol(sema: sema, interner: interner)

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testCCallAnnotationHasFunctionTarget() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cCallSymbol(sema: sema, interner: interner)
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "CCall must carry @Target metadata"
        )

        XCTAssertTrue(
            target.arguments.contains("AnnotationTarget.FUNCTION"),
            "CCall must target FUNCTION; got \(target.arguments)"
        )
    }

    func testCCallAnnotationHasBinaryRetention() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cCallSymbol(sema: sema, interner: interner)
        let retention = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "CCall must carry @Retention metadata"
        )

        XCTAssertTrue(
            retention.arguments.contains("AnnotationRetention.BINARY"),
            "CCall must have BINARY retention; got \(retention.arguments)"
        )
    }
}
