@testable import CompilerCore
import Foundation
import XCTest

final class NativeCInteropInternalCStructAnnotationTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected CStruct surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func cStructSymbol(sema: SemaModule, interner: StringInterner) throws -> SymbolID {
        try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "internal", "CStruct"].map { interner.intern($0) }),
            "kotlinx.cinterop.internal.CStruct must be registered"
        )
    }

    func testCStructAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cStructSymbol(sema: sema, interner: interner)

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testCStructAnnotationHasClassTarget() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cStructSymbol(sema: sema, interner: interner)
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "CStruct must carry @Target metadata"
        )

        XCTAssertTrue(
            target.arguments.contains("AnnotationTarget.CLASS"),
            "CStruct must target CLASS; got \(target.arguments)"
        )
    }

    func testCStructAnnotationHasBinaryRetention() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cStructSymbol(sema: sema, interner: interner)
        let retention = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "CStruct must carry @Retention metadata"
        )

        XCTAssertTrue(
            retention.arguments.contains("AnnotationRetention.BINARY"),
            "CStruct must have BINARY retention; got \(retention.arguments)"
        )
    }

    func testCStructIsInCInteropInternalPackage() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cStructSymbol(sema: sema, interner: interner)
        let fqName = try XCTUnwrap(sema.symbols.symbol(symbol)?.fqName)
        let expectedPkg = ["kotlinx", "cinterop", "internal"].map { interner.intern($0) }

        XCTAssertTrue(
            fqName.starts(with: expectedPkg),
            "CStruct must reside in kotlinx.cinterop.internal; got fqName: \(fqName)"
        )
    }
}
