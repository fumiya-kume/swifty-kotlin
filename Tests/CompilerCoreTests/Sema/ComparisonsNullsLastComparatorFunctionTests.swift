@testable import CompilerCore
import XCTest

final class ComparisonsNullsLastComparatorFunctionTests: XCTestCase {
    func testNullsLastComparatorFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsLast
        import kotlin.comparisons.naturalOrder

        fun makeComparator(): Comparator<Int?> {
            return nullsLast(naturalOrder<Int>())
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
