@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-068: Validates that `CharSequence.slice(indices)` resolves
/// through Sema for `String` receivers using both overloads.
///
/// - IntRange overload — `s.slice(0..3)` — links to `kk_string_slice`.
/// - Iterable<Int> overload — `s.slice(listOf(0, 2, 4))` — links to
///   `kk_string_slice_iterable`.
final class StringSliceFunctionTests: XCTestCase {
    func testSliceWithIntRangeResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun pickPrefix(s: String): String {
            return s.slice(0..3)
        }

        fun pickFromExpression(): String {
            return "Kotlin".slice(2..5)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected slice(IntRange) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testSliceWithListOfIntResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun pickByIndices(s: String): String {
            return s.slice(listOf(0, 2, 4))
        }

        fun pickFromLiteral(): String {
            return "abcdef".slice(listOf(5, 3, 1))
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected slice(Iterable<Int>) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    /// Both overloads are registered in the symbol table with distinct external link
    /// names so that the call-lowering phase can dispatch to the correct runtime
    /// helper based on the argument shape.
    func testSliceOverloadsLinkToDistinctRuntimeHelpers() throws {
        var resolved: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            resolved = (sema, ctx.interner)
        }
        let (sema, interner) = try XCTUnwrap(resolved)

        let sliceFQ = ["kotlin", "text", "slice"].map { interner.intern($0) }
        let allSliceSymbols = sema.symbols.lookupAll(fqName: sliceFQ)
        let externalLinks = Set(allSliceSymbols.compactMap { sema.symbols.externalLinkName(for: $0) })
        XCTAssertTrue(
            externalLinks.contains("kk_string_slice"),
            "slice(IntRange) should link to kk_string_slice; got \(externalLinks)"
        )
        XCTAssertTrue(
            externalLinks.contains("kk_string_slice_iterable"),
            "slice(Iterable<Int>) should link to kk_string_slice_iterable; got \(externalLinks)"
        )
    }
}
