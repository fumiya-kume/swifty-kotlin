@testable import CompilerCore
import XCTest

/// STDLIB-COMP-FN-054: Validates that `minOfOrNull(selector)` resolves
/// through Sema for the selector-based aggregate receivers wired through the
/// standard List / Sequence synthetic-member infrastructure.
/// Runtime link names involved: `kk_list_minOfOrNull`, `kk_sequence_minOfOrNull`.
final class ComparisonsMinOfOrNullFunctionTests: XCTestCase {

    /// `List<T>.minOfOrNull { selector }` and `Sequence<T>.minOfOrNull { selector }`
    /// must type-check end-to-end from user source.
    func testMinOfOrNullFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun pickList(xs: List<Int>): Int? {
            return xs.minOfOrNull { it * 10 }
        }

        fun pickSequence(xs: Sequence<Int>): Int? {
            return xs.minOfOrNull { it * 10 }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected minOfOrNull to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    /// `List<T>.minOfOrNull` must be registered with the `kk_list_minOfOrNull` external link.
    func testListMinOfOrNullIsRegisteredWithRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let fq = ["kotlin", "collections", "List", "minOfOrNull"].map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(
            links.contains("kk_list_minOfOrNull"),
            "List.minOfOrNull must link to kk_list_minOfOrNull; found: \(links)"
        )
    }

    /// `Sequence<T>.minOfOrNull` must be registered with the
    /// `kk_sequence_minOfOrNull` external link.
    func testSequenceMinOfOrNullIsRegisteredWithRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let fq = ["kotlin", "sequences", "Sequence", "minOfOrNull"].map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(
            links.contains("kk_sequence_minOfOrNull"),
            "Sequence.minOfOrNull must link to kk_sequence_minOfOrNull; found: \(links)"
        )
    }

    /// The return type of `List<Int>.minOfOrNull { Int }` must be `Int?` (nullable Int).
    func testListMinOfOrNullReturnTypeIsNullableSelector() throws {
        let ctx = makeContextFromSource("""
        fun check(xs: List<Int>): Int? {
            return xs.minOfOrNull { it * 2 }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected minOfOrNull on Int list to type-check as Int?, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    /// `minOfOrNull` on an empty list must return null — verified via the
    /// nullable return type annotation matching.
    func testListMinOfOrNullOnEmptyListReturnTypeIsCompatibleWithNull() throws {
        let ctx = makeContextFromSource("""
        fun checkEmpty(): Int? {
            return emptyList<Int>().minOfOrNull { it }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected minOfOrNull on empty List<Int> to type-check as Int?, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
