@testable import CompilerCore
import XCTest

/// STDLIB-SEQ-FN-111: Validates that `kotlin.sequences.Sequence<T>.sortedBy`
/// resolves through Sema and is wired to the runtime bridge.
/// Runtime link name: `kk_sequence_sortedBy`.
final class SequenceSortedByFunctionTests: XCTestCase {
    func testSequenceSortedByFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun sortByLength(values: Sequence<String>): Sequence<String> {
            return values.sortedBy { it.length }
        }

        fun sortByLengthFromGenerator(): Sequence<String> {
            return sequenceOf("cc", "a", "bbb").sortedBy { value -> value.length }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Sequence.sortedBy to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try XCTUnwrap(ctx.sema)
        let memberFQName = ["kotlin", "sequences", "Sequence", "sortedBy"]
            .map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(
            links.contains("kk_sequence_sortedBy"),
            "Expected Sequence.sortedBy to link to kk_sequence_sortedBy, got: \(links)"
        )
    }
}
