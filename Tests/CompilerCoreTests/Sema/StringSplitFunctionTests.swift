@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-069: Validates that `CharSequence.split(delimiter, ignoreCase, limit)`
/// resolves through Sema for `String` receivers across all registered overloads.
///
/// Overload links (see `HeaderHelpers+SyntheticStringStubs.swift`):
/// - `split(delimiters: String)` → `kk_string_split`
/// - `split(delimiters: String, limit: Int)` → `kk_string_split_limit`
/// - `split(delimiters: String, ignoreCase: Bool)` → `kk_string_split_limit`
/// - `split(delimiters: String, ignoreCase: Bool, limit: Int)` → `kk_string_split_limit`
final class StringSplitFunctionTests: XCTestCase {
    func testSplitWithDelimiterResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun splitCsv(s: String): List<String> {
            return s.split(",")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected split(delimiter) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testSplitWithLimitResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun splitFirstTwo(s: String): List<String> {
            return s.split(",", limit = 2)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected split(delimiter, limit) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testSplitWithIgnoreCaseResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun splitIgnoringCase(s: String): List<String> {
            return s.split("x", ignoreCase = true)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected split(delimiter, ignoreCase) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testSplitWithIgnoreCaseAndLimitResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun splitIgnoringCaseWithLimit(s: String): List<String> {
            return s.split("x", ignoreCase = true, limit = 3)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected split(delimiter, ignoreCase, limit) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testSplitOnStringLiteralResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun parts(): List<String> {
            return "a,b,c".split(",")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected split on a String literal to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
