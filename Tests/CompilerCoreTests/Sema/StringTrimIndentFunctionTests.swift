@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-112: `kotlin.text.String.trimIndent()`
///
/// `trimIndent()` は複数行文字列リテラルから共通の最小インデント
/// (スペース・タブ) を取り除く拡張関数。Sema が `kk_string_trimIndent`
/// 外部リンク名に解決し、戻り値型が `String` になることを検証する。
final class StringTrimIndentFunctionTests: XCTestCase {
    func testTrimIndentOnStringLiteralResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "    hello".trimIndent()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testTrimIndentOnStringVariableResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val source: String = "  line"
            val dedented: String = source.trimIndent()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testTrimIndentAcceptsNoArguments() throws {
        // Pass an unexpected positional argument; Sema should reject it.
        let ctx = makeContextFromSource("""
        fun main() {
            val s = "abc".trimIndent(1)
        }
        """)
        try runSema(ctx)
        XCTAssertTrue(
            ctx.diagnostics.hasError,
            "expected error for extra argument, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    func testTrimIndentReturnTypeIsString() throws {
        // The return must be a String so subsequent String members (length) resolve.
        let ctx = makeContextFromSource("""
        fun main() {
            val n: Int = "    abcde".trimIndent().length
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }

    func testTrimIndentChainableWithOtherStringMembers() throws {
        // trimIndent() must return a String compatible with subsequent String APIs.
        let ctx = makeContextFromSource("""
        fun main() {
            val s: String = "  abc".trimIndent().trim()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
