@testable import CompilerCore
import XCTest

final class SystemMeasureNanoTimeFunctionTests: XCTestCase {
    func testMeasureNanoTimeFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.system.measureNanoTime

        fun timeIt(): Long {
            return measureNanoTime {
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
