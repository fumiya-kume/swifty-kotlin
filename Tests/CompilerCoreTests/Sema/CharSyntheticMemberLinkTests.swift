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
            "lowercaseChar": "kk_char_lowercaseChar",
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

    func testCharCategoryEnumSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let charCategorySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("CharCategory"),
        ]))
        XCTAssertEqual(sema.symbols.symbol(charCategorySymbol)?.kind, .enumClass)

        let charCategoryType = sema.types.make(.classType(ClassType(
            classSymbol: charCategorySymbol,
            args: [],
            nullability: .nonNull
        )))
        let entries = [
            "UNASSIGNED",
            "UPPERCASE_LETTER",
            "LOWERCASE_LETTER",
            "TITLECASE_LETTER",
            "MODIFIER_LETTER",
            "OTHER_LETTER",
            "NON_SPACING_MARK",
            "ENCLOSING_MARK",
            "COMBINING_SPACING_MARK",
            "DECIMAL_DIGIT_NUMBER",
            "LETTER_NUMBER",
            "OTHER_NUMBER",
            "SPACE_SEPARATOR",
            "LINE_SEPARATOR",
            "PARAGRAPH_SEPARATOR",
            "CONTROL",
            "FORMAT",
            "PRIVATE_USE",
            "SURROGATE",
            "DASH_PUNCTUATION",
            "START_PUNCTUATION",
            "END_PUNCTUATION",
            "CONNECTOR_PUNCTUATION",
            "OTHER_PUNCTUATION",
            "MATH_SYMBOL",
            "CURRENCY_SYMBOL",
            "MODIFIER_SYMBOL",
            "OTHER_SYMBOL",
            "INITIAL_QUOTE_PUNCTUATION",
            "FINAL_QUOTE_PUNCTUATION",
        ]

        for entry in entries {
            let entrySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("text"),
                interner.intern("CharCategory"),
                interner.intern(entry),
            ]), "CharCategory.\(entry) must be registered")
            XCTAssertEqual(sema.symbols.propertyType(for: entrySymbol), charCategoryType)
        }
    }

    func testCharCategoryPropertyReturnsCharCategoryEnum() throws {
        let (sema, interner) = try makeSema()

        let charCategorySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("CharCategory"),
        ]))
        let categoryFunction = try XCTUnwrap(sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("category"),
        ]).first { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.receiverType == sema.types.charType
        })
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: categoryFunction))
        guard case let .classType(categoryClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Char.category should return kotlin.text.CharCategory")
        }
        XCTAssertEqual(categoryClassType.classSymbol, charCategorySymbol)
    }

    func testCharDirectionalityReturnsEnumType() throws {
        let (sema, interner) = try makeSema()

        let enumFQName = ["kotlin", "text", "CharDirectionality"].map { interner.intern($0) }
        let enumSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName))
        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        let directionalityFQName = ["kotlin", "text", "directionality"].map { interner.intern($0) }
        let directionalitySymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: directionalityFQName).first { symbolID in
            sema.symbols.functionSignature(for: symbolID)?.receiverType == sema.types.charType
        })
        XCTAssertEqual(sema.symbols.functionSignature(for: directionalitySymbol)?.returnType, enumType)

        for entry in ["UNDEFINED", "LEFT_TO_RIGHT", "RIGHT_TO_LEFT_ARABIC", "COMMON_NUMBER_SEPARATOR", "WHITESPACE"] {
            let entrySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName + [interner.intern(entry)]))
            XCTAssertEqual(sema.symbols.propertyType(for: entrySymbol), enumType)
        }
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
            ch.lowercaseChar()
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
                "lowercaseChar": "kk_char_lowercaseChar",
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
