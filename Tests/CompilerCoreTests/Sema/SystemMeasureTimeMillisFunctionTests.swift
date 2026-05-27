@testable import CompilerCore
import XCTest

final class SystemMeasureTimeMillisFunctionTests: XCTestCase {
    func testMeasureTimeMillisFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.system.measureTimeMillis

        fun timeIt(): Long {
            return measureTimeMillis {
                var sum = 0
                for (i in 1..100) {
                    sum += i
                }
            }
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
