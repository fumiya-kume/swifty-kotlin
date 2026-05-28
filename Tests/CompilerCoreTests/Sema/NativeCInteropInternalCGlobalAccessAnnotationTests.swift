@testable import CompilerCore
import Foundation
import XCTest

final class NativeCInteropInternalCGlobalAccessAnnotationTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected CGlobalAccess surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func cGlobalAccessSymbol(sema: SemaModule, interner: StringInterner) throws -> SymbolID {
        try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "internal", "CGlobalAccess"].map { interner.intern($0) }),
            "kotlinx.cinterop.internal.CGlobalAccess must be registered"
        )
    }

    func testCGlobalAccessAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cGlobalAccessSymbol(sema: sema, interner: interner)

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testCGlobalAccessAnnotationHasPropertyTarget() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cGlobalAccessSymbol(sema: sema, interner: interner)
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "CGlobalAccess must carry @Target metadata"
        )

        XCTAssertTrue(
            target.arguments.contains("AnnotationTarget.PROPERTY"),
            "CGlobalAccess must target PROPERTY; got \(target.arguments)"
        )
    }

    func testCGlobalAccessAnnotationHasBinaryRetention() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cGlobalAccessSymbol(sema: sema, interner: interner)
        let retention = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "CGlobalAccess must carry @Retention metadata"
        )

        XCTAssertTrue(
            retention.arguments.contains("AnnotationRetention.BINARY"),
            "CGlobalAccess must have BINARY retention; got \(retention.arguments)"
        )
    }

    func testCGlobalAccessIsInCInteropInternalPackage() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cGlobalAccessSymbol(sema: sema, interner: interner)
        let fqName = try XCTUnwrap(sema.symbols.symbol(symbol)?.fqName)
        let expectedPkg = ["kotlinx", "cinterop", "internal"].map { interner.intern($0) }

        XCTAssertTrue(
            fqName.starts(with: expectedPkg),
            "CGlobalAccess must reside in kotlinx.cinterop.internal; got fqName: \(fqName)"
        )
    }
}
