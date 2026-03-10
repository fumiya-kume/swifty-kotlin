@testable import CompilerCore
import Foundation
import XCTest

/// Verifies that the new String stdlib extension stubs added in the PR
/// (STDLIB-006, STDLIB-009) are registered in the symbol table with the
/// correct runtime external link names.
final class StringSyntheticMemberLinkTests: XCTestCase {
    /// Resolve the `kotlin.text.<member>` symbol and return its external link name.
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testExistingStringStubsRetainCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "trim": "kk_string_trim",
            "split": "kk_string_split",
            "replace": "kk_string_replace",
            "startsWith": "kk_string_startsWith",
            "endsWith": "kk_string_endsWith",
            "toInt": "kk_string_toInt",
            "toDouble": "kk_string_toDouble",
            "trimIndent": "kk_string_trimIndent",
        ]

        for (member, expectedLink) in expected {
            XCTAssertEqual(
                externalLink(for: member, sema: sema, interner: interner),
                expectedLink,
                "String.\(member) should link to \(expectedLink)"
            )
        }
    }

    func testNewCaseConversionStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "lowercase", sema: sema, interner: interner),
            "kk_string_lowercase",
            "String.lowercase should link to kk_string_lowercase"
        )
        XCTAssertEqual(
            externalLink(for: "uppercase", sema: sema, interner: interner),
            "kk_string_uppercase",
            "String.uppercase should link to kk_string_uppercase"
        )
    }

    func testNewNullableConversionStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "toIntOrNull", sema: sema, interner: interner),
            "kk_string_toIntOrNull",
            "String.toIntOrNull should link to kk_string_toIntOrNull"
        )
        XCTAssertEqual(
            externalLink(for: "toDoubleOrNull", sema: sema, interner: interner),
            "kk_string_toDoubleOrNull",
            "String.toDoubleOrNull should link to kk_string_toDoubleOrNull"
        )
    }

    func testNewSubstringAndSearchStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "indexOf": "kk_string_indexOf",
            "lastIndexOf": "kk_string_lastIndexOf",
        ]
        for (member, expectedLink) in expected {
            XCTAssertEqual(
                externalLink(for: member, sema: sema, interner: interner),
                expectedLink,
                "String.\(member) should link to \(expectedLink)"
            )
        }
    }

    func testNewTransformStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "repeat": "kk_string_repeat",
            "reversed": "kk_string_reversed",
            "toList": "kk_string_toList",
            "toCharArray": "kk_string_toCharArray",
        ]
        for (member, expectedLink) in expected {
            XCTAssertEqual(
                externalLink(for: member, sema: sema, interner: interner),
                expectedLink,
                "String.\(member) should link to \(expectedLink)"
            )
        }
    }

    func testNewPaddingStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        XCTAssertEqual(
            externalLink(for: "padStart", sema: sema, interner: interner),
            "kk_string_padStart",
            "String.padStart should link to kk_string_padStart"
        )
        XCTAssertEqual(
            externalLink(for: "padEnd", sema: sema, interner: interner),
            "kk_string_padEnd",
            "String.padEnd should link to kk_string_padEnd"
        )
    }

    func testNewSlicingStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "drop": "kk_string_drop",
            "take": "kk_string_take",
            "dropLast": "kk_string_dropLast",
            "takeLast": "kk_string_takeLast",
        ]
        for (member, expectedLink) in expected {
            XCTAssertEqual(
                externalLink(for: member, sema: sema, interner: interner),
                expectedLink,
                "String.\(member) should link to \(expectedLink)"
            )
        }
    }

    func testNewStringMembersResolveInCallExpressions() throws {
        let source = """
        fun process(s: String): String {
            val lower = s.lowercase()
            val upper = s.uppercase()
            val rep = s.repeat(3)
            val rev = s.reversed()
            return lower + upper + rep + rev
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedLinks: [String: String] = [
                "lowercase": "kk_string_lowercase",
                "uppercase": "kk_string_uppercase",
                "repeat": "kk_string_repeat",
                "reversed": "kk_string_reversed",
            ]

            for (memberName, externalLinkName) in expectedLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for \(memberName)"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }
}
