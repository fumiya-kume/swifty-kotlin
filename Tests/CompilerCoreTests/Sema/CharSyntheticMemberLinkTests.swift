@testable import CompilerCore
import Foundation
import XCTest

final class CharSyntheticMemberLinkTests: XCTestCase {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        let sym = sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == sema.types.charType
        } ?? sema.symbols.lookup(fqName: fq)
        guard let sym else { return nil }
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
            "digitToInt": "kk_char_digitToInt",
            "digitToIntOrNull": "kk_char_digitToIntOrNull",
            // New numeric conversion functions
            "toInt": "kk_char_toInt",
            "toDouble": "kk_char_toDouble",
            "toIntOrNull": "kk_char_toIntOrNull",
            "toDoubleOrNull": "kk_char_toDoubleOrNull",
            // Code point and Unicode properties
            "code": "kk_char_code",
            "category": "kk_char_category",
            "directionality": "kk_char_directionality",
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
            ch.digitToInt()
            ch.digitToIntOrNull()
            ch.uppercase()
            ch.lowercase()
            ch.titlecase()
            // New numeric conversion functions
            ch.toInt()
            ch.toDouble()
            ch.toIntOrNull()
            ch.toDoubleOrNull()
            // Code point and Unicode properties
            ch.code
            ch.category
            ch.directionality
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedFunctionLinks: [String: String] = [
                "isDigit": "kk_char_isDigit",
                "isLetter": "kk_char_isLetter",
                "isLetterOrDigit": "kk_char_isLetterOrDigit",
                "isWhitespace": "kk_char_isWhitespace",
                "digitToInt": "kk_char_digitToInt",
                "digitToIntOrNull": "kk_char_digitToIntOrNull",
                "uppercase": "kk_char_uppercase",
                "lowercase": "kk_char_lowercase",
                "titlecase": "kk_char_titlecase",
                "toInt": "kk_char_toInt",
                "toDouble": "kk_char_toDouble",
                "toIntOrNull": "kk_char_toIntOrNull",
                "toDoubleOrNull": "kk_char_toDoubleOrNull",
            ]
            let expectedPropertyLinks: [String: String] = [
                "code": "kk_char_code",
                "category": "kk_char_category",
                "directionality": "kk_char_directionality",
            ]

            for (memberName, externalLinkName) in expectedFunctionLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                XCTAssertNotEqual(sema.bindings.exprTypes[callExpr], sema.types.errorType)
                if let chosenCallee = sema.bindings.callBinding(for: callExpr)?.chosenCallee
                    ?? sema.bindings.identifierSymbol(for: callExpr)
                {
                    XCTAssertEqual(
                        sema.symbols.externalLinkName(for: chosenCallee),
                        externalLinkName,
                        "Expected \(memberName) to resolve to \(externalLinkName)"
                    )
                }
            }

            for (memberName, externalLinkName) in expectedPropertyLinks {
                let propertyExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName && args.isEmpty
                }, "Expected property access to \(memberName) in AST")
                XCTAssertNotEqual(sema.bindings.exprTypes[propertyExpr], sema.types.errorType)
                if let chosenSymbol = sema.bindings.identifierSymbol(for: propertyExpr) {
                    XCTAssertEqual(
                        sema.symbols.externalLinkName(for: chosenSymbol),
                        externalLinkName,
                        "Expected \(memberName) to resolve to \(externalLinkName)"
                    )
                }
            }
        }
    }
}
