@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-103: `fun String.toLongOrNull(): Long?` in `kotlin.text`.
///
/// Verifies:
/// - The synthetic stub registered for `String.toLongOrNull` links to the
///   runtime symbol `kk_string_toLongOrNull` declared in
///   `Sources/RuntimeABI/RuntimeABISpec+String.swift`.
/// - The extension resolves cleanly from source code and produces no Sema
///   diagnostics for a call returning `Long?`.
final class StringToLongOrNullFunctionTests: XCTestCase {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func externalLinks(for member: String, sema: SemaModule, interner: StringInterner) -> Set<String> {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        return Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
    }

    func testToLongOrNullStubLinksToRuntimeSymbol() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            XCTAssertEqual(
                externalLink(for: "toLongOrNull", sema: sema, interner: ctx.interner),
                "kk_string_toLongOrNull",
                "String.toLongOrNull should link to kk_string_toLongOrNull"
            )

            let links = externalLinks(for: "toLongOrNull", sema: sema, interner: ctx.interner)
            XCTAssertTrue(
                links.contains("kk_string_toLongOrNull"),
                "lookupAll for toLongOrNull must include kk_string_toLongOrNull; got: \(links)"
            )
        }
    }

    func testToLongOrNullResolvesOnStringReceiver() throws {
        let source = """
        fun parse(raw: String): Long? {
            return raw.toLongOrNull()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected String.toLongOrNull to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }
}
