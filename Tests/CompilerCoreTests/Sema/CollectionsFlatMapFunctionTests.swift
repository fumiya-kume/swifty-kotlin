@testable import CompilerCore
import XCTest

final class CollectionsFlatMapFunctionTests: XCTestCase {
    func testFlatMapFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun expand(xs: List<Int>): List<Int> {
            return xs.flatMap { listOf(it, it * 2) }
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
