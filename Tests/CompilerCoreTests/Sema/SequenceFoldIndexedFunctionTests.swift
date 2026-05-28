@testable import CompilerCore
import XCTest

/// STDLIB-SEQ-FN-043: Validates that `Sequence<T>.foldIndexed` resolves through
/// Sema and gets wired to the runtime entry point `kk_sequence_foldIndexed`.
/// The synthetic surface signature is `foldIndexed(initial: R, operation: (Int, R, T) -> R): R`.
final class SequenceFoldIndexedFunctionTests: XCTestCase {
    func testSequenceFoldIndexedResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun indexedSum(): Int {
            return sequenceOf(3, 4, 5).foldIndexed(0) { index, acc, value ->
                acc + index * 10 + value
            }
        }

        fun indexedConcat(): String {
            return sequenceOf("a", "b", "c").foldIndexed("") { index, acc, value ->
                acc + "$index:$value;"
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Sequence.foldIndexed to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testSequenceFoldIndexedLinksToRuntimeEntryPoint() throws {
        let source = """
        fun indexedTotal(): Int {
            return sequenceOf(1, 2, 3).foldIndexed(10) { index, acc, value ->
                acc + index + value
            }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected Sequence.foldIndexed surface to resolve cleanly, got: \(diagnosticSummary)"
        )

        let sema = try XCTUnwrap(ctx.sema)
        let memberFQName = ["kotlin", "sequences", "Sequence", "foldIndexed"]
            .map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(
            links.contains("kk_sequence_foldIndexed"),
            "Expected Sequence.foldIndexed to link to kk_sequence_foldIndexed, got: \(links)"
        )
    }
}
