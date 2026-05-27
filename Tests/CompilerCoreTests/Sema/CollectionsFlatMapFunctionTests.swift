@testable import CompilerCore
import XCTest

/// STDLIB-COL-FN-075: Validates that `flatMap` resolves through Sema for the
/// collection receivers wired through the standard transform infrastructure —
/// `List<T>` / `Set<T>` / `Map<K, V>` / `Sequence<T>`. The transform is
/// expected to accept either an `Iterable<R>` or a `Sequence<R>` and the
/// result type is the flattened collection / sequence of `R`.
/// Runtime link names involved: `kk_list_flatMap`, `kk_set_flatMap`,
/// `kk_map_flatMap`, `kk_sequence_flatMap`.
final class CollectionsFlatMapFunctionTests: XCTestCase {
    func testFlatMapFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun flattenList(xs: List<Int>): List<Int> {
            return xs.flatMap { listOf(it, it * 2) }
        }

        fun flattenSet(xs: Set<Int>): List<Int> {
            return xs.flatMap { listOf(it) }
        }

        fun flattenMap(m: Map<String, Int>): List<Int> {
            return m.flatMap { entry -> listOf(entry.value) }
        }

        fun flattenSequence(s: Sequence<Int>): Sequence<Int> {
            return s.flatMap { sequenceOf(it, it + 1) }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected flatMap to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
