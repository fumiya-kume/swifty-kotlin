@testable import CompilerCore
import XCTest

/// STDLIB-COL-FN-073: Validates that `firstNotNullOfOrNull` resolves through Sema
/// across the standard receivers wired through the surface registration —
/// `List<T>` / `Set<T>` / `Iterable<T>` / `Sequence<T>` / `String`.
///
/// Per-receiver behavior is exercised by `IterableFirstNotNullOfOrNullSemaTests`
/// and `SequenceFirstNotNullOfOrNullSemaTests`; this suite focuses on the
/// `kotlin.collections.firstNotNullOfOrNull` surface as a whole, mirroring the
/// structure of `CollectionsFirstOrNullFunctionTests`.
///
/// Runtime link names involved: `kk_iterable_firstNotNullOfOrNull`,
/// `kk_sequence_firstNotNullOfOrNull`, `kk_string_firstNotNullOfOrNull`.
final class FirstNotNullOfOrNullFunctionTests: XCTestCase {
    func testFirstNotNullOfOrNullFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun firstHitList(xs: List<Int>): String? {
            return xs.firstNotNullOfOrNull { if (it > 0) "hit" else null }
        }

        fun firstHitSet(xs: Set<Int>): String? {
            return xs.firstNotNullOfOrNull { if (it > 0) "hit" else null }
        }

        fun firstHitIterable(xs: Iterable<Int>): String? {
            return xs.firstNotNullOfOrNull { if (it > 0) "hit" else null }
        }

        fun firstHitSequence(xs: Sequence<Int>): String? {
            return xs.firstNotNullOfOrNull { if (it > 0) "hit" else null }
        }

        fun firstHitString(s: String): String? {
            return s.firstNotNullOfOrNull { if (it == 'x') "hit" else null }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected firstNotNullOfOrNull to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
