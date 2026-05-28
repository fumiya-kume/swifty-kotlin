@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-019: `kotlin.text.String.indent(n: Int)`
///
/// `indent(n)` は各行の先頭に n 個のスペースを付加（n < 0 なら最大 |n| 個除去）し、
/// 末尾に改行を付けて返す拡張関数。Sema が `kk_string_indent` 外部リンク名に
/// 解決し、戻り値型が `String` になることを検証する。
final class StringIndentFunctionTests: XCTestCase {

    func testIndentOnStringLiteralResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "hello".indent(4)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testIndentOnStringVariableResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val source: String = "line1\\nline2"
            val indented: String = source.indent(2)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testIndentWithNegativeNResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "  hello".indent(-2)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testIndentWithZeroResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "hello".indent(0)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testIndentRequiresIntArgument() throws {
        // Passing no argument should be rejected by Sema.
        let ctx = makeContextFromSource("""
        fun main() {
            val s = "abc".indent()
        }
        """)
        try runSema(ctx)
        XCTAssertTrue(
            ctx.diagnostics.hasError,
            "expected error for missing argument, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testIndentReturnTypeIsString() throws {
        // The return must be a String so subsequent String members (length) resolve.
        let ctx = makeContextFromSource("""
        fun main() {
            val n: Int = "hello".indent(2).length
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testIndentChainableWithOtherStringMembers() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "  hello".indent(2).trim()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
