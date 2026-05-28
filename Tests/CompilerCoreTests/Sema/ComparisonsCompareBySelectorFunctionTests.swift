@testable import CompilerCore
import XCTest

final class ComparisonsCompareBySelectorFunctionTests: XCTestCase {
    func testCompareBySelectorFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.compareBy

        data class Person(val age: Int)

        fun makeComparator(): Comparator<Person> {
            return compareBy<Person> { it.age }
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected compareBy(selector) to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
