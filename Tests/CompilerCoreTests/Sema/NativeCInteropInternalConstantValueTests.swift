@testable import CompilerCore
import Foundation
import XCTest

final class NativeCInteropInternalConstantValueTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected ConstantValue surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func constantValueSymbol(sema: SemaModule, interner: StringInterner) throws -> SymbolID {
        try XCTUnwrap(
            sema.symbols.lookup(
                fqName: ["kotlinx", "cinterop", "internal", "ConstantValue"].map { interner.intern($0) }
            ),
            "kotlinx.cinterop.internal.ConstantValue must be registered"
        )
    }

    func testConstantValueAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let symbol = try constantValueSymbol(sema: sema, interner: interner)

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testConstantValueAnnotationHasPropertyTarget() throws {
        let (sema, interner) = try makeSema()
        let symbol = try constantValueSymbol(sema: sema, interner: interner)
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "ConstantValue must carry @Target metadata"
        )

        XCTAssertTrue(
            target.arguments.contains("AnnotationTarget.PROPERTY"),
            "ConstantValue must target PROPERTY; got \(target.arguments)"
        )
    }

    func testConstantValueAnnotationHasBinaryRetention() throws {
        let (sema, interner) = try makeSema()
        let symbol = try constantValueSymbol(sema: sema, interner: interner)
        let retention = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "ConstantValue must carry @Retention metadata"
        )

        XCTAssertTrue(
            retention.arguments.contains("AnnotationRetention.BINARY"),
            "ConstantValue must have BINARY retention; got \(retention.arguments)"
        )
    }
}
