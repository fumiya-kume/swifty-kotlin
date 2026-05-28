@testable import CompilerCore
import XCTest

/// STDLIB-COMP-FN-061: kotlin.comparisons.nullsLast() top-level function (Comparable version).
///
/// Verifies that the no-arg `nullsLast<T: Comparable<T>>(): Comparator<T?>` overload is
/// registered in the symbol table, links to `kk_comparator_nulls_last_natural`, and
/// resolves correctly from source code.
final class ComparisonsNullsLastComparableFunctionTests: XCTestCase {

    // MARK: - Symbol table

    func testNullsLastNaturalIsRegisteredWithCorrectLink() throws {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        let (sema, interner) = try XCTUnwrap(result)

        let interned = ["kotlin", "comparisons", "nullsLast"].map { interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: interned)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        XCTAssertTrue(
            links.contains("kk_comparator_nulls_last_natural"),
            "kotlin.comparisons.nullsLast (no-arg) must link to kk_comparator_nulls_last_natural; found: \(links)"
        )
    }

    // MARK: - Source resolution

    func testNullsLastComparableFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.nullsLast

        fun makeComparator(): Comparator<Int?> {
            return nullsLast<Int>()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
