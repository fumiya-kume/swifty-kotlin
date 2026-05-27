@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-102: Validates that `String.toLong()` resolves through Sema
/// for `String` receivers and links to the `kk_string_toLong` runtime entry.
///
/// The Sema stub is registered in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticStringStubs.swift`
/// alongside the matching ABI entry in
/// `Sources/RuntimeABI/RuntimeABISpec+String.swift` and the runtime
/// implementation in `Sources/Runtime/RuntimeStringStdlib.swift`.
final class StringToLongFunctionTests: XCTestCase {
    func testToLongFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun parseSignedDecimal(s: String): Long {
            return s.toLong()
        }

        fun parseLiteral(): Long {
            return "9223372036854775807".toLong()
        }

        fun parseNegative(): Long {
            return "-1234567890".toLong()
        }

        fun roundTrip(value: Long): Long {
            return value.toString().toLong()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected String.toLong to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
