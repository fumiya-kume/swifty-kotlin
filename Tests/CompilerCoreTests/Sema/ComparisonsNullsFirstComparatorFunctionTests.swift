@testable import CompilerCore
import XCTest

final class ComparisonsNullsFirstComparatorFunctionTests: XCTestCase {
    func testNullsFirstComparatorFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsFirst
        import kotlin.comparisons.naturalOrder

        fun makeComparator(): Comparator<Int?> {
            return nullsFirst(naturalOrder<Int>())
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
