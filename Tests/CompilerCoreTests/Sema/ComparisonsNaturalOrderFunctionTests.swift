@testable import CompilerCore
import XCTest

final class ComparisonsNaturalOrderFunctionTests: XCTestCase {
    func testNaturalOrderFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.naturalOrder

        fun makeComparator(): Comparator<Int> {
            return naturalOrder<Int>()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
