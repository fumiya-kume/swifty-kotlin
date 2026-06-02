@testable import CompilerCore
import XCTest

final class ComparisonsMaxOfComparable2FunctionTests: XCTestCase {
    func testMaxOfComparable2ArgFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.maxOf

        data class Version(val value: Int) : Comparable<Version> {
            override fun compareTo(other: Version): Int = value - other.value
        }

        fun pickLatest(a: Version, b: Version): Version {
            return maxOf(a, b)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected maxOf(a, b) Comparable 2-arg overload to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
