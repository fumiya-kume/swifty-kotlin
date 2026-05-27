@testable import CompilerCore
import XCTest

/// STDLIB-SEQ-FN-095: Validates that `Sequence<T>.reduceRightIndexed` resolves
/// through Sema using the standard synthetic terminal stub. The lambda receives
/// `(index: Int, value: T, acc: S) -> S` and the call must bind to the runtime
/// link `kk_sequence_reduceRightIndexed`.
final class SequenceReduceRightIndexedFunctionTests: XCTestCase {
    func testReduceRightIndexedFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun foldSequence(values: Sequence<Int>): Int {
            return values.reduceRightIndexed { index, value, acc -> index * 100 + value * 10 + acc }
        }

        fun foldSequenceWithNamedArgument(values: Sequence<Int>): Int {
            return values.reduceRightIndexed(operation = { index, value, acc -> index + value + acc })
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Sequence.reduceRightIndexed to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
