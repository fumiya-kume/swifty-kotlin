@testable import CompilerCore
import XCTest

final class ComparisonsNullsFirstFunctionTests: XCTestCase {
    func testNullsFirstFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsFirst

        fun makeComparator(): Comparator<Int?> {
            return nullsFirst<Int>()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
