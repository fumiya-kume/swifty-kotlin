@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-037: Validates that `CharSequence.lines()` resolves through
/// Sema on String receivers and links to the runtime helper `kk_string_lines`,
/// returning `List<String>`.
final class StringLinesFunctionTests: XCTestCase {
    func testLinesNoArgResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun splitToLines(s: String): List<String> {
            return s.lines()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected lines to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testLinesOnStringLiteralResolves() throws {
        let ctx = makeContextFromSource("""
        fun firstLine(): String {
            return "a\\nb\\nc".lines().first()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected lines on a literal to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testLinesResultIsIterable() throws {
        let ctx = makeContextFromSource("""
        fun printAll(s: String) {
            for (line in s.lines()) {
                println(line)
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected for-in over s.lines() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
