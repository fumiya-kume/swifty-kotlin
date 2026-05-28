@testable import CompilerCore
import XCTest

/// STDLIB-SEQ-FN-093: Validates that `kotlin.sequences.Sequence<T>.reduceOrNull`
/// resolves through Sema for the canonical surfaces used at call sites
/// (single-arg `(T, T) -> T` accumulator that returns `T?`).
/// Runtime link name involved: `kk_sequence_reduceOrNull`.
final class SequenceReduceOrNullFunctionTests: XCTestCase {
    func testReduceOrNullFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun reduceSequence(): Int? {
            return sequenceOf(1, 2, 3, 4).reduceOrNull { acc, value -> acc + value }
        }

        fun reduceEmptySequence(): Int? {
            return emptySequence<Int>().reduceOrNull { acc, value -> acc + value }
        }

        fun reduceSequenceStrings(): String? {
            return sequenceOf("a", "b", "c").reduceOrNull { acc, value -> acc + value }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Sequence.reduceOrNull to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
