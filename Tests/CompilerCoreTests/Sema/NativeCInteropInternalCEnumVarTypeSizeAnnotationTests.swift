@testable import CompilerCore
import XCTest

final class NativeCInteropInternalCEnumVarTypeSizeAnnotationTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected CEnumVarTypeSize surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        return (sema, ctx.interner)
    }

    private func cEnumVarTypeSizeSymbol(sema: SemaModule, interner: StringInterner) throws -> SymbolID {
        try XCTUnwrap(
            sema.symbols.lookup(
                fqName: ["kotlinx", "cinterop", "internal", "CEnumVarTypeSize"].map { interner.intern($0) }
            ),
            "kotlinx.cinterop.internal.CEnumVarTypeSize must be registered"
        )
    }

    func testCEnumVarTypeSizeAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cEnumVarTypeSizeSymbol(sema: sema, interner: interner)

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testCEnumVarTypeSizeAnnotationHasClassTarget() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cEnumVarTypeSizeSymbol(sema: sema, interner: interner)
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "CEnumVarTypeSize must carry @Target metadata"
        )

        XCTAssertTrue(
            target.arguments.contains("AnnotationTarget.CLASS"),
            "CEnumVarTypeSize must target CLASS; got \(target.arguments)"
        )
    }

    func testCEnumVarTypeSizeAnnotationHasBinaryRetention() throws {
        let (sema, interner) = try makeSema()
        let symbol = try cEnumVarTypeSizeSymbol(sema: sema, interner: interner)
        let retention = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "CEnumVarTypeSize must carry @Retention metadata"
        )

        XCTAssertTrue(
            retention.arguments.contains("AnnotationRetention.BINARY"),
            "CEnumVarTypeSize must have BINARY retention; got \(retention.arguments)"
        )
    }
}
