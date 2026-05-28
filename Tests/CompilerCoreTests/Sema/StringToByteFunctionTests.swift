@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-090: Validates that `String.toByte()` and `String.toByte(radix)`
/// resolve through Sema as extension functions in `kotlin.text`.
///
/// - The no-arg overload links to `kk_string_toByte`.
/// - The radix overload links to `kk_string_toByte_radix`.
final class StringToByteFunctionTests: XCTestCase {
    func testToByteNoArgResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun parseByte(s: String): Int {
            return s.toByte().toInt()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected toByte() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testToByteWithRadixResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun parseHexByte(s: String): Int {
            return s.toByte(16).toInt()
        }

        fun parseBinaryByte(s: String): Int {
            return s.toByte(2).toInt()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected toByte(radix) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testToByteLiteralReceiverResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun decimal(): Int {
            return "42".toByte().toInt()
        }

        fun hex(): Int {
            return "7f".toByte(16).toInt()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected toByte literal calls to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
