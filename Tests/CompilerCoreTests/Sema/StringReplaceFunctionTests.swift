@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-055: Validates that `CharSequence.replace(oldValue, newValue, ignoreCase)`
/// resolves through Sema for `String` receivers using both the 2-arg and 3-arg overloads.
///
/// - 2-arg overload links to `kk_string_replace`.
/// - 3-arg overload (with `ignoreCase: Boolean`) links to `kk_string_replace_ignoreCase`.
final class StringReplaceFunctionTests: XCTestCase {
    func testReplaceTwoArgOverloadResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun replaceAll(s: String, target: String, with: String): String {
            return s.replace(target, with)
        }

        fun replaceLiteral(): String {
            return "abcabc".replace("a", "z")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected replace(2-arg) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testReplaceWithIgnoreCaseResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun replaceIgnoreCase(s: String, target: String, with: String, flag: Boolean): String {
            return s.replace(target, with, flag)
        }

        fun replaceIgnoreCaseLiteralTrue(): String {
            return "ABcabc".replace("ab", "z", true)
        }

        fun replaceIgnoreCaseLiteralFalse(): String {
            return "ABcabc".replace("ab", "z", false)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected replace(3-arg) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testReplaceIgnoreCaseExternalLinkIsRegistered() throws {
        var captured: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            captured = (sema, ctx.interner)
        }
        let (sema, interner) = try XCTUnwrap(captured)

        let fq = ["kotlin", "text", "replace"].map { interner.intern($0) }
        let externalLinks = Set(
            sema.symbols.lookupAll(fqName: fq).compactMap {
                sema.symbols.externalLinkName(for: $0)
            }
        )
        XCTAssertTrue(
            externalLinks.contains("kk_string_replace"),
            "String.replace(old, new) should link to kk_string_replace; got \(externalLinks)"
        )
        XCTAssertTrue(
            externalLinks.contains("kk_string_replace_ignoreCase"),
            "String.replace(old, new, ignoreCase) should link to kk_string_replace_ignoreCase; got \(externalLinks)"
        )
    }
}
