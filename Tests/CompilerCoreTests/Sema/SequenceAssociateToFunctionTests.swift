@testable import CompilerCore
import XCTest

/// STDLIB-SEQ-FN-008: Validates that `Sequence<T>.associateTo(destination, transform)`
/// resolves through Sema, populating a `MutableMap<K, V>` using the Pair-returning
/// transform and returning the destination map.
/// Runtime link name involved: `kk_sequence_associateTo`.
final class SequenceAssociateToFunctionTests: XCTestCase {
    func testSequenceAssociateToResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun fillByLength(): MutableMap<Int, String> {
            val dest = mutableMapOf<Int, String>()
            return sequenceOf("a", "bb", "ccc").associateTo(dest) { value ->
                Pair(value.length, value)
            }
        }

        fun fillByFirstChar(words: Sequence<String>): MutableMap<Char, String> {
            val dest = mutableMapOf<Char, String>()
            return words.associateTo(dest) { Pair(it[0], it) }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Sequence.associateTo to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
