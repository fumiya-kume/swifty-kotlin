@testable import CompilerCore
import Foundation
import XCTest

final class CharSyntheticMemberLinkTests: XCTestCase {
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

    func testCharPredicateStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "isDigit": "kk_char_isDigit",
            "isLetter": "kk_char_isLetter",
            "isLetterOrDigit": "kk_char_isLetterOrDigit",
            "isWhitespace": "kk_char_isWhitespace",
        ]

        for (member, expectedLink) in expected {
            XCTAssertEqual(
                externalLink(for: member, sema: sema, interner: interner),
                expectedLink,
                "Char.\(member) should link to \(expectedLink)"
            )
        }
    }

    func testKotlinTextPackageIsParentedUnderKotlinPackage() throws {
        let (sema, interner) = try makeSema()

        let kotlinSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("kotlin")]))
        let kotlinTextSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("text")])
        )

        XCTAssertEqual(sema.symbols.parentSymbol(for: kotlinTextSymbol), kotlinSymbol)
    }

    func testCharPredicateMembersResolveInCallExpressions() throws {
        let source = """
        fun probe(ch: Char) {
            ch.isDigit()
            ch.isLetter()
            ch.isLetterOrDigit()
            ch.isWhitespace()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedLinks: [String: String] = [
                "isDigit": "kk_char_isDigit",
                "isLetter": "kk_char_isLetter",
                "isLetterOrDigit": "kk_char_isLetterOrDigit",
                "isWhitespace": "kk_char_isWhitespace",
            ]

            for (memberName, externalLinkName) in expectedLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }
}
