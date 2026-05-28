@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-020: Validates that `kotlin.text.CharSequence.indexOf` resolves
/// through Sema for both the String-search overloads and the new Char overload.
/// Runtime link names involved:
/// - `kk_string_indexOf` (single String argument)
/// - `kk_string_indexOf_from` (String + startIndex)
/// - `kk_string_indexOf_ignoreCase` (String + startIndex + ignoreCase)
/// - `kk_string_indexOf_char` (Char + optional startIndex + optional ignoreCase)
final class StringIndexOfFunctionTests: XCTestCase {
    func testIndexOfStringResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun findToken(s: String): Int {
            return s.indexOf("token")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected indexOf(String) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIndexOfStringWithStartIndexResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun findFromOffset(s: String): Int {
            return s.indexOf("token", 3)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected indexOf(String, startIndex) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIndexOfStringWithStartIndexAndIgnoreCaseResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun findCaseInsensitive(s: String): Int {
            return s.indexOf("Token", 0, true)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected indexOf(String, startIndex, ignoreCase) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIndexOfCharResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun findChar(s: String): Int {
            return s.indexOf('x')
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected indexOf(Char) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIndexOfCharWithStartIndexResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun findCharFromOffset(s: String): Int {
            return s.indexOf('x', 2)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected indexOf(Char, startIndex) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIndexOfCharWithStartIndexAndIgnoreCaseResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun findCharCaseInsensitive(s: String): Int {
            return s.indexOf('X', 0, true)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected indexOf(Char, startIndex, ignoreCase) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
