@testable import CompilerCore
import Foundation
import XCTest

final class NativeCInteropInternalCEnumEntryAliasAnnotationTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected CEnumEntryAlias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func cEnumEntryAliasSymbol(sema: SemaModule, interner: StringInterner) throws -> SymbolID {
        try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "internal", "CEnumEntryAlias"].map { interner.intern($0) }),
            "kotlinx.cinterop.internal.CEnumEntryAlias must be registered"
        )
    }

    func testCEnumEntryAliasAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cEnumEntryAliasSymbol(sema: sema, interner: interner)

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testCEnumEntryAliasAnnotationHasPropertyTarget() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cEnumEntryAliasSymbol(sema: sema, interner: interner)
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "CEnumEntryAlias must carry @Target metadata"
        )

        XCTAssertTrue(
            target.arguments.contains("AnnotationTarget.PROPERTY"),
            "CEnumEntryAlias must target PROPERTY; got \(target.arguments)"
        )
    }

    func testCEnumEntryAliasAnnotationHasBinaryRetention() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cEnumEntryAliasSymbol(sema: sema, interner: interner)
        let retention = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "CEnumEntryAlias must carry @Retention metadata"
        )

        XCTAssertTrue(
            retention.arguments.contains("AnnotationRetention.BINARY"),
            "CEnumEntryAlias must have BINARY retention; got \(retention.arguments)"
        )
    }

    func testCEnumEntryAliasIsInCInteropInternalPackage() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cEnumEntryAliasSymbol(sema: sema, interner: interner)
        let fqName = try XCTUnwrap(sema.symbols.symbol(symbol)?.fqName)
        let expectedPkg = ["kotlinx", "cinterop", "internal"].map { interner.intern($0) }

        XCTAssertTrue(
            fqName.starts(with: expectedPkg),
            "CEnumEntryAlias must reside in kotlinx.cinterop.internal; got fqName: \(fqName)"
        )
    }
}
