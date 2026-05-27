@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-SEQ-FN-030: Validates that `Sequence<T>.filterNotTo` resolves through Sema
/// to the runtime ABI entry point (`kk_sequence_filterNotTo`). The destination-argument
/// HOF appends elements that do NOT match the predicate to the supplied mutable
/// collection and returns the destination.
final class SequenceFilterNotToFunctionTests: XCTestCase {
    func testSequenceFilterNotToResolvesInSource() throws {
        let source = """
        fun rejectEvens(values: Sequence<Int>): MutableList<Int> {
            val destination = mutableListOf<Int>()
            return values.filterNotTo(destination) { value -> value % 2 == 0 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected Sequence.filterNotTo to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "filterNotTo"]
                .map(ctx.interner.intern)
            let sequenceMembers = sema.symbols.lookupAll(fqName: memberFQName)

            XCTAssertTrue(
                sequenceMembers.contains { sema.symbols.externalLinkName(for: $0) == "kk_sequence_filterNotTo" },
                "Expected Sequence.filterNotTo synthetic member to link to kk_sequence_filterNotTo"
            )
        }
    }
}
