@testable import CompilerCore
import XCTest

final class ComparisonsCompareByDescendingSelectorFunctionTests: XCTestCase {
    func testCompareByDescendingSelectorFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.compareByDescending

        data class Person(val age: Int)

        fun makeComparator(): Comparator<Person> {
            return compareByDescending<Person> { it.age }
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected compareByDescending(selector) to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
