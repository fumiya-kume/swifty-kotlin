@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-SEQ-FN-040: Validates that `Sequence<T>.flatMapIndexedTo` resolves
/// through Sema for the `kotlin.sequences.Sequence` receiver wired through
/// the standard HOF infrastructure. The transform receives the element index
/// and value and returns an `Iterable<R>` whose contents are appended to the
/// destination `MutableCollection<R>`. The call is linked to the runtime
/// symbol `kk_sequence_flatMapIndexedTo` and the call expression is typed as
/// the destination collection type.
final class SequenceFlatMapIndexedToFunctionTests: XCTestCase {
    func testSequenceFlatMapIndexedToResolvesToRuntimeABIAndDestinationResult() throws {
        let source = """
        fun probe(values: Sequence<Int>): MutableList<String> {
            val dest: MutableList<String> = mutableListOf()
            return values.flatMapIndexedTo(dest) { index, value ->
                listOf(index.toString(), value.toString())
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected flatMapIndexedTo to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = [
                "kotlin", "sequences", "Sequence", "flatMapIndexedTo",
            ].map { ctx.interner.intern($0) }
            let sequenceMembers = sema.symbols.lookupAll(fqName: memberFQName)
            XCTAssertTrue(
                sequenceMembers.contains { sema.symbols.externalLinkName(for: $0) == "kk_sequence_flatMapIndexedTo" },
                "Expected Sequence.flatMapIndexedTo synthetic member to link to kk_sequence_flatMapIndexedTo"
            )
        }
    }
}
