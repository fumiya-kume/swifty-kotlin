@testable import CompilerCore
import XCTest

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
