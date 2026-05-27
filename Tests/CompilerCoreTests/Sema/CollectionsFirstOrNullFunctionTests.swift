@testable import CompilerCore
import XCTest

/// STDLIB-COL-FN-074: Validates that `firstOrNull` resolves through Sema for the
/// collection receivers wired through the standard aggregate / HOF infrastructure
/// — `List<T>` / `Set<T>` (no-arg) and `Range` (no-arg and predicate overloads).
/// Runtime link names involved: `kk_list_firstOrNull`, `kk_set_firstOrNull`,
/// `kk_range_firstOrNull`, `kk_range_firstOrNull_predicate`.
final class CollectionsFirstOrNullFunctionTests: XCTestCase {
    func testFirstOrNullFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun maybeFirstList(xs: List<Int>): Int? {
            return xs.firstOrNull()
        }

        fun maybeFirstSet(xs: Set<Int>): Int? {
            return xs.firstOrNull()
        }

        fun maybeFirstRange(): Int? {
            return (1..10).firstOrNull()
        }

        fun maybeFirstRangeMatching(): Int? {
            return (1..10).firstOrNull { it > 5 }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected firstOrNull to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
