@testable import CompilerCore
import XCTest

/// STDLIB-COMP-FN-056: Validates that `minWithOrNull(comparator)` resolves
/// through Sema for the comparator-based aggregate receivers wired through the
/// standard List / Sequence synthetic-member infrastructure.
/// Runtime link names involved: `kk_list_minWithOrNull`, `kk_sequence_minWithOrNull`.
final class ComparisonsMinWithOrNullFunctionTests: XCTestCase {

    /// `List<T>.minWithOrNull(Comparator)` and `Sequence<T>.minWithOrNull(Comparator)`
    /// must type-check end-to-end from user source.
    func testMinWithOrNullFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun pickList(xs: List<Int>, cmp: Comparator<Int>): Int? {
            return xs.minWithOrNull(cmp)
        }

        fun pickSequence(xs: Sequence<Int>, cmp: Comparator<Int>): Int? {
            return xs.minWithOrNull(cmp)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected minWithOrNull to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    /// `List<T>.minWithOrNull` must be registered with the `kk_list_minWithOrNull` external link.
    func testListMinWithOrNullIsRegisteredWithRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let fq = ["kotlin", "collections", "List", "minWithOrNull"].map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(
            links.contains("kk_list_minWithOrNull"),
            "List.minWithOrNull must link to kk_list_minWithOrNull; found: \(links)"
        )
    }

    /// `Sequence<T>.minWithOrNull` must be registered with the
    /// `kk_sequence_minWithOrNull` external link.
    func testSequenceMinWithOrNullIsRegisteredWithRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let fq = ["kotlin", "sequences", "Sequence", "minWithOrNull"].map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(
            links.contains("kk_sequence_minWithOrNull"),
            "Sequence.minWithOrNull must link to kk_sequence_minWithOrNull; found: \(links)"
        )
    }
}
