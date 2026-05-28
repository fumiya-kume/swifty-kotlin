@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-018: Validates that `String.get(index)` operator resolves
/// through Sema for `String` receivers, dispatching to the runtime link name
/// `kk_string_get`.
final class StringGetFunctionTests: XCTestCase {
    func testGetByNameResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun firstChar(s: String): Char {
            return s.get(0)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected String.get(Int) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testIndexedAccessOnStringResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun charAt(s: String, i: Int): Char {
            return s[i]
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected indexed access on String to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testGetOnStringLiteralResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun firstOfHello(): Char {
            return "hello".get(0)
        }

        fun secondOfHello(): Char {
            return "hello"[1]
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected String.get/indexed access on literal to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
