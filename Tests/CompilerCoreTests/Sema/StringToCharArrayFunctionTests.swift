@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-093: Validates that `String.toCharArray()` resolves through Sema
/// and links to the `kk_string_toCharArray` runtime entry.
///
/// The synthetic extension function is registered in
/// `HeaderHelpers+SyntheticStringStubs.swift`, the call lowering routes to the
/// runtime symbol in `CallLowerer+LegacyMemberLikeCalls.swift`, and the runtime
/// implementation lives in `Sources/Runtime/RuntimeStringStdlib.swift`.
final class StringToCharArrayFunctionTests: XCTestCase {
    func testToCharArrayResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun explode(s: String): CharArray {
            return s.toCharArray()
        }

        fun explodeLiteral(): CharArray {
            return "hello".toCharArray()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected toCharArray to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testToCharArrayChainedAsCharArrayReceiverResolves() throws {
        // Validates that the returned CharArray supports CharArray-level members
        // — i.e. the inferred return type really is CharArray, not e.g. List<Char>.
        let ctx = makeContextFromSource("""
        fun countChars(s: String): Int {
            return s.toCharArray().size
        }

        fun firstChar(s: String): Char {
            return s.toCharArray()[0]
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected toCharArray chained access to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
