@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-SEQ-FN-027: Validates that `Sequence<*>.filterIsInstanceTo<R>` resolves through Sema
/// to the runtime ABI entry point (`kk_sequence_filterIsInstanceTo`). The destination-argument
/// HOF appends elements matching the given runtime type to the supplied mutable collection
/// and returns the destination.
final class SequenceFilterIsInstanceToFunctionTests: XCTestCase {
    func testSequenceFilterIsInstanceToResolvesInSource() throws {
        let source = """
        fun collectInts(values: Sequence<Any>): MutableList<Int> {
            val destination = mutableListOf<Int>()
            return values.filterIsInstanceTo(destination)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected Sequence.filterIsInstanceTo to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let memberFQName = ["kotlin", "sequences", "Sequence", "filterIsInstanceTo"]
                .map(ctx.interner.intern)
            let sequenceMembers = sema.symbols.lookupAll(fqName: memberFQName)

            XCTAssertTrue(
                sequenceMembers.contains { sema.symbols.externalLinkName(for: $0) == "kk_sequence_filterIsInstanceTo" },
                "Expected Sequence.filterIsInstanceTo synthetic member to link to kk_sequence_filterIsInstanceTo"
            )
        }
    }
}
