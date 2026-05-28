@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-012: Validates that `CharSequence.contains` resolves through
/// Sema for `String` receivers across all of its stdlib overloads. The synthetic
/// stubs register:
/// - `contains(other: String)` → `kk_string_contains_str` (also acts as the
///   `in` operator on strings).
/// - `contains(other: String, ignoreCase: Boolean)` → `kk_string_contains_ignoreCase`
/// - `contains(regex: Regex)` → `kk_string_contains_regex`
final class StringContainsFunctionTests: XCTestCase {
    func testContainsWithStringResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun hasSubstring(s: String): Boolean {
            return s.contains("hello")
        }

        fun emptyNeedleAlwaysMatches(s: String): Boolean {
            return s.contains("")
        }

        fun literalReceiverContains(): Boolean {
            return "hello world".contains("world")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected contains(String) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testContainsWithIgnoreCaseResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun hasSubstringIgnoreCase(s: String): Boolean {
            return s.contains("HELLO", true)
        }

        fun explicitCaseSensitive(s: String, needle: String): Boolean {
            return s.contains(needle, false)
        }

        fun namedIgnoreCase(s: String): Boolean {
            return s.contains("foo", ignoreCase = true)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected contains(String, Boolean) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testContainsInOperatorResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun substringViaInOperator(s: String, needle: String): Boolean {
            return needle in s
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected `in` operator on String to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    /// Verifies the chosen callee for the 2-arg overload is wired to the
    /// case-insensitive runtime entry point. This is the contract that keeps
    /// `s.contains(x, true)` from silently dropping `ignoreCase` and dispatching
    /// to `kk_string_contains_str` instead.
    func testContainsIgnoreCaseLinksToRuntime() throws {
        let ctx = makeContextFromSource("""
        fun hasSubstringIgnoreCase(s: String, needle: String): Boolean {
            return s.contains(needle, true)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "expected contains to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let containsFQName: [InternedString] = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("text"),
            ctx.interner.intern("contains"),
        ]
        let sema = try XCTUnwrap(ctx.sema)
        let resolvedSymbols = sema.symbols.lookupAll(fqName: containsFQName)
        let hasIgnoreCaseLink = resolvedSymbols.contains { symbolID in
            sema.symbols.externalLinkName(for: symbolID) == "kk_string_contains_ignoreCase"
        }
        XCTAssertTrue(
            hasIgnoreCaseLink,
            "Expected a `kotlin.text/contains` symbol to expose externalLinkName=kk_string_contains_ignoreCase"
        )
    }
}
