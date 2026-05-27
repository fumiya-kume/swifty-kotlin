@testable import CompilerCore
import XCTest

/// STDLIB-COMP-FN-027: kotlin.comparisons.maxWith (3-arg comparator form).
///
/// Verifies that
/// `fun <T> maxWith(comparator: Comparator<in T>, a: T, b: T): T`
/// is registered as a synthetic stub in the kotlin.comparisons package and
/// resolves cleanly from user source code.
final class ComparisonsMaxWithFunctionTests: XCTestCase {
    func testMaxWithFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.maxWith
        import kotlin.comparisons.naturalOrder

        fun biggerOf(a: Int, b: Int): Int {
            return maxWith(naturalOrder<Int>(), a, b)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
