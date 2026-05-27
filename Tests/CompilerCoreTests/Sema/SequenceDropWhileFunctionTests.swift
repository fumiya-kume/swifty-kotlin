@testable import CompilerCore
import XCTest

/// STDLIB-SEQ-FN-019: Validates that `dropWhile` resolves through Sema for the
/// `kotlin.sequences.Sequence<T>` receiver wired through the standard sequence
/// HOF infrastructure.
/// Runtime link name involved: `kk_sequence_dropWhile`.
final class SequenceDropWhileFunctionTests: XCTestCase {
    func testDropWhileFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun tail(values: Sequence<Int>): Sequence<Int> {
            return values.dropWhile { value -> value < 3 }
        }

        fun tailWithIt(values: Sequence<Int>): Sequence<Int> {
            return values.dropWhile { it < 3 }
        }

        fun pipeline(values: Sequence<Int>): List<Int> {
            return values
                .dropWhile { it == 0 }
                .map { it * 2 }
                .toList()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Sequence.dropWhile to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
