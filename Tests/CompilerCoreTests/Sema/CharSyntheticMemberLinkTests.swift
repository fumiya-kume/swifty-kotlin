@testable import CompilerCore
import Foundation
import XCTest

final class CharSyntheticMemberLinkTests: XCTestCase {
    private let charCategoryEntries = [
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

    private func charCategorySymbol(sema: SemaModule, interner: StringInterner) throws -> SymbolID {
        try XCTUnwrap(sema.symbols.lookup(fqName: ["kotlin", "text", "CharCategory"].map { interner.intern($0) }))
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

    func testCharCategoryEnumSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let enumSymbol = try charCategorySymbol(sema: sema, interner: interner)
        XCTAssertEqual(sema.symbols.symbol(enumSymbol)?.kind, .enumClass)

        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entry in charCategoryEntries {
            let entrySymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: ["kotlin", "text", "CharCategory", entry].map { interner.intern($0) }),
                "CharCategory.\(entry) must be registered"
            )
            XCTAssertEqual(sema.symbols.parentSymbol(for: entrySymbol), enumSymbol)
            XCTAssertEqual(sema.symbols.propertyType(for: entrySymbol), enumType)
        }
    }

    func testCharCategoryMembersAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let enumSymbol = try charCategorySymbol(sema: sema, interner: interner)
        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        let codeSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "text", "CharCategory", "code"].map { interner.intern($0) })
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: codeSymbol), "kk_char_category_code")
        let codeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: codeSymbol))
        XCTAssertEqual(codeSignature.receiverType, enumType)
        XCTAssertEqual(codeSignature.parameterTypes, [])
        XCTAssertEqual(codeSignature.returnType, sema.types.stringType)

        let containsSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "text", "CharCategory", "contains"].map { interner.intern($0) })
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: containsSymbol), "kk_char_category_contains")
        let containsSignature = try XCTUnwrap(sema.symbols.functionSignature(for: containsSymbol))
        XCTAssertEqual(containsSignature.receiverType, enumType)
        XCTAssertEqual(containsSignature.parameterTypes, [sema.types.charType])
        XCTAssertEqual(containsSignature.returnType, sema.types.booleanType)
    }

    func testCharCategoryPropertyReturnsEnumType() throws {
        let (sema, interner) = try makeSema()
        let enumSymbol = try charCategorySymbol(sema: sema, interner: interner)
        let categorySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: ["kotlin", "text", "category"].map { interner.intern($0) }).first { symbolID in
                sema.symbols.functionSignature(for: symbolID)?.receiverType == sema.types.charType
            }
        )
        let returnType = try XCTUnwrap(sema.symbols.functionSignature(for: categorySymbol)?.returnType)
        guard case let .classType(classType) = sema.types.kind(of: returnType) else {
            return XCTFail("Char.category should return kotlin.text.CharCategory")
        }
        XCTAssertEqual(classType.classSymbol, enumSymbol)
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

    func testCharCategoryUsageResolvesInSource() throws {
        let source = """
        fun probe(ch: Char): Boolean {
            val category: CharCategory = ch.category
            val code: String = category.code
            return CharCategory.UPPERCASE_LETTER.contains(ch) && code.length > 0
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "CharCategory enum entries, Char.category, code, and contains should resolve: \(ctx.diagnostics.diagnostics)"
            )
        }
    }
}
