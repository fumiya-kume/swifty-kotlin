@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-010: Validates that `CharSequence.codePointCount` resolves
/// through Sema for `String` / `CharSequence` receivers.
///
/// The synthetic stub registers:
/// - `codePointCount(beginIndex: Int, endIndex: Int): Int`
///   → `kk_string_codePointCount`
final class StringCodePointCountFunctionTests: XCTestCase {
    func testCodePointCountResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun countCodePoints(s: String): Int {
            return s.codePointCount(0, s.length)
        }

        fun countRange(s: String, start: Int, end: Int): Int {
            return s.codePointCount(start, end)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected codePointCount(Int, Int) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCodePointCountLinksToRuntime() throws {
        let ctx = makeContextFromSource("""
        fun countCodePoints(s: String): Int {
            return s.codePointCount(0, s.length)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected codePointCount to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let fqName: [InternedString] = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("text"),
            ctx.interner.intern("codePointCount"),
        ]
        let sema = try XCTUnwrap(ctx.sema)
        let resolvedSymbols = sema.symbols.lookupAll(fqName: fqName)
        let hasLink = resolvedSymbols.contains { symbolID in
            sema.symbols.externalLinkName(for: symbolID) == "kk_string_codePointCount"
        }
        XCTAssertTrue(
            hasLink,
            "Expected a `kotlin.text/codePointCount` symbol with externalLinkName=kk_string_codePointCount"
        )
    }

    func testCodePointCountReturnTypeIsInt() throws {
        let ctx = makeContextFromSource("""
        fun getCount(s: String): Int {
            return s.codePointCount(0, 1)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected codePointCount return type Int to satisfy Int return, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
