@testable import CompilerCore
import XCTest

final class CollectionsFirstNotNullOfOrNullFunctionTests: XCTestCase {
    func testFirstNotNullOfOrNullFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun firstPositive(xs: List<Int>): String? {
            return xs.firstNotNullOfOrNull { if (it > 0) it.toString() else null }
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
