@testable import CompilerCore
import XCTest

/// STDLIB-COMP-FN-055: Validates that `minWith(comparator)` resolves through
/// Sema for the receivers wired through the standard aggregate / HOF
/// infrastructure — `List<T>` and `Sequence<T>`. The companion runtime entry
/// points are `kk_list_minWith` and `kk_sequence_minWith`.
final class ComparisonsMinWithFunctionTests: XCTestCase {
    func testMinWithFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.naturalOrder

        fun smallestList(xs: List<Int>): Int {
            return xs.minWith(naturalOrder<Int>())
        }

        fun smallestSequence(xs: Sequence<Int>): Int {
            return xs.minWith(naturalOrder<Int>())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected minWith to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
