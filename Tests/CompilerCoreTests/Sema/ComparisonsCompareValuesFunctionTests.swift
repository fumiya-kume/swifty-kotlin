@testable import CompilerCore
import XCTest

final class ComparisonsCompareValuesFunctionTests: XCTestCase {
    func testCompareValuesFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.compareValues

        fun cmp(a: Int?, b: Int?): Int {
            return compareValues(a, b)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
