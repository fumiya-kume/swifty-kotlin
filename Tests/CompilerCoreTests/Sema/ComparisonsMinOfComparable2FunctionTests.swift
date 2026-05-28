@testable import CompilerCore
import XCTest

final class ComparisonsMinOfComparable2FunctionTests: XCTestCase {
    func testMinOfComparable2ArgFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.minOf

        data class Version(val value: Int) : Comparable<Version> {
            override fun compareTo(other: Version): Int = value - other.value
        }

        fun pickEarliest(a: Version, b: Version): Version {
            return minOf(a, b)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected minOf(a, b) Comparable 2-arg overload to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
