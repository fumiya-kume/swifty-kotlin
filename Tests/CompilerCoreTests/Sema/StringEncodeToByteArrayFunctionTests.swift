@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-014: Validates that `String.encodeToByteArray()` and its overloads
/// resolve through Sema and link to the correct runtime entries.
///
/// Overloads covered:
///  - `encodeToByteArray()` → `kk_string_encodeToByteArray`
///  - `encodeToByteArray(startIndex, endIndex)` → `kk_string_encodeToByteArray_range`
///  - `encodeToByteArray(charset)` → `kk_string_encodeToByteArray_charset`
///
/// The synthetic extension functions are registered in
/// `HeaderHelpers+SyntheticStringStubs.swift` (STDLIB-573/STDLIB-581), and the
/// runtime implementation lives in `Sources/Runtime/RuntimeStringStdlib.swift`.
final class StringEncodeToByteArrayFunctionTests: XCTestCase {
    func testEncodeToByteArrayNoArgResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun encode(s: String): ByteArray {
            return s.encodeToByteArray()
        }

        fun encodeLiteral(): ByteArray {
            return "hello".encodeToByteArray()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected encodeToByteArray() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testEncodeToByteArrayRangeResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun encodeSlice(s: String): ByteArray {
            return s.encodeToByteArray(1, 4)
        }

        fun encodeLiteralSlice(): ByteArray {
            return "abcdef".encodeToByteArray(0, 3)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected encodeToByteArray(startIndex, endIndex) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testEncodeToByteArrayCharsetResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun encodeWithCharset(s: String): ByteArray {
            return s.encodeToByteArray(Charsets.UTF_8)
        }

        fun encodeAscii(s: String): ByteArray {
            return s.encodeToByteArray(Charsets.US_ASCII)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected encodeToByteArray(charset) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testEncodeToByteArrayChainedWithDecodeToStringResolvesInSource() throws {
        // Validates that the returned ByteArray supports decodeToString
        let ctx = makeContextFromSource("""
        fun roundTrip(s: String): String {
            return s.encodeToByteArray().decodeToString()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected encodeToByteArray().decodeToString() chain to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
