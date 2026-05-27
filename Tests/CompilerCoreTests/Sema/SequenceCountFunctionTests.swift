@testable import CompilerCore
import XCTest

/// STDLIB-SEQ-FN-015: Validates that `kotlin.sequences.Sequence<T>.count()`
/// resolves through Sema for the no-argument receiver wired through the
/// standard Sequence terminal / HOF infrastructure.
/// Runtime link name involved: `kk_sequence_count`.
final class SequenceCountFunctionTests: XCTestCase {
    func testSequenceCountFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun countSeq(): Int {
            return sequenceOf(1, 2, 3).count()
        }

        fun countFiltered(): Int {
            return sequenceOf(1, 2, 3, 4).filter { it % 2 == 0 }.count()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Sequence.count to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try XCTUnwrap(ctx.sema)
        let memberFQName = ["kotlin", "sequences", "Sequence", "count"]
            .map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(
            links.contains("kk_sequence_count"),
            "Expected kk_sequence_count link to be registered, got: \(links)"
        )
    }
}
