@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-PROP-019: Validates that `Char.isWhitespace` resolves through Sema
/// as a member function on the `Char` receiver. The synthetic stub is registered
/// in `HeaderHelpers+SyntheticCharStubs.swift` and links to the runtime export
/// `kk_char_isWhitespace` (see `Sources/Runtime/RuntimeChar.swift`).
final class CharIsWhitespaceFunctionTests: XCTestCase {
    func testIsWhitespaceFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun probeSpace(): Boolean {
            return ' '.isWhitespace()
        }

        fun probeTab(): Boolean {
            return '\\t'.isWhitespace()
        }

        fun probeLetter(): Boolean {
            return 'A'.isWhitespace()
        }

        fun probeVar(ch: Char): Boolean {
            return ch.isWhitespace()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected Char.isWhitespace to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
