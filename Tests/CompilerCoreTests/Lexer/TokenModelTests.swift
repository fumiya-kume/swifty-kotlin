import XCTest
@testable import CompilerCore

final class TokenModelTests: XCTestCase {
    func testStringInternerReusesIDsAndResolvesInternedValues() {
        let interner = StringInterner()

        let fooA = interner.intern("foo")
        let fooB = interner.intern("foo")
        let bar = interner.intern("bar")

        XCTAssertEqual(fooA, fooB)
        XCTAssertNotEqual(fooA, bar)
        XCTAssertEqual(interner.resolve(fooA), "foo")
        XCTAssertEqual(interner.resolve(bar), "bar")
    }

    func testStringInternerResolveReturnsEmptyForOutOfRangeIDs() {
        let interner = StringInterner()
        _ = interner.intern("only")

        XCTAssertEqual(interner.resolve(InternedString(rawValue: -1)), "")
        XCTAssertEqual(interner.resolve(InternedString(rawValue: 100)), "")
    }

    func testTriviaPieceBlockCommentAndShebang() {
        let block = TriviaPiece.blockComment("/* comment */")
        let shebang = TriviaPiece.shebang("#!/usr/bin/env kotlin")
        XCTAssertNotEqual(block, shebang)
        XCTAssertEqual(block, .blockComment("/* comment */"))
        XCTAssertEqual(shebang, .shebang("#!/usr/bin/env kotlin"))
    }

    func testTokenKindMissingBacktickedIdentifierAndCharLiteral() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 1)

        let missing = Token(kind: .missing(expected: .keyword(.fun)), range: range)
        XCTAssertEqual(missing.kind, .missing(expected: .keyword(.fun)))

        let backticked = Token(kind: .backtickedIdentifier(interner.intern("myFun")), range: range)
        guard case .backtickedIdentifier(let name) = backticked.kind else {
            return XCTFail("Expected backtickedIdentifier")
        }
        XCTAssertEqual(interner.resolve(name), "myFun")

        let charLit = Token(kind: .charLiteral(65), range: range)
        guard case .charLiteral(let code) = charLit.kind else {
            return XCTFail("Expected charLiteral")
        }
        XCTAssertEqual(code, 65)
    }

    func testInternedStringInvalidAndEquality() {
        XCTAssertEqual(InternedString.invalid.rawValue, -1)
        XCTAssertEqual(InternedString(), InternedString.invalid)
        XCTAssertNotEqual(InternedString(rawValue: 0), InternedString(rawValue: 1))
    }

    func testTokenInitializerHandlesDefaultsAndExplicitTrivia() {
        let range = makeRange(start: 0, end: 4)
        let defaultToken = Token(kind: .keyword(.fun), range: range)
        XCTAssertEqual(defaultToken.leadingTrivia, [])
        XCTAssertEqual(defaultToken.trailingTrivia, [])

        let token = Token(
            kind: .symbol(.plus),
            range: range,
            leadingTrivia: [.spaces(1), .tabs(1)],
            trailingTrivia: [.newline, .lineComment("// trailing")]
        )
        XCTAssertEqual(token.kind, .symbol(.plus))
        XCTAssertEqual(token.range, range)
        XCTAssertEqual(token.leadingTrivia, [.spaces(1), .tabs(1)])
        XCTAssertEqual(token.trailingTrivia, [.newline, .lineComment("// trailing")])
    }

    // MARK: - Keyword enum: all cases

    func testKeywordAllCasesRawValues() {
        let expectedKeywords: [(Keyword, String)] = [
            (.as, "as"),
            (.break, "break"),
            (.class, "class"),
            (.catch, "catch"),
            (.continue, "continue"),
            (.data, "data"),
            (.do, "do"),
            (.else, "else"),
            (.false, "false"),
            (.dynamic, "dynamic"),
            (.enum, "enum"),
            (.external, "external"),
            (.for, "for"),
            (.fun, "fun"),
            (.if, "if"),
            (.infix, "infix"),
            (.in, "in"),
            (.is, "is"),
            (.import, "import"),
            (.interface, "interface"),
            (.finally, "finally"),
            (.null, "null"),
            (.operator, "operator"),
            (.object, "object"),
            (.package, "package"),
            (.return, "return"),
            (.super, "super"),
            (.this, "this"),
            (.typealias, "typealias"),
            (.throw, "throw"),
            (.true, "true"),
            (.try, "try"),
            (.val, "val"),
            (.var, "var"),
            (.while, "while"),
            (.when, "when"),
            (.sealed, "sealed"),
            (.inner, "inner"),
            (.reified, "reified"),
            (.open, "open"),
            (.private, "private"),
            (.public, "public"),
            (.protected, "protected"),
            (.internal, "internal"),
            (.override, "override"),
            (.final, "final"),
            (.abstract, "abstract"),
            (.suspend, "suspend"),
            (.inline, "inline"),
            (.expect, "expect"),
            (.actual, "actual"),
            (.constructor, "constructor"),
            (.companion, "companion"),
            (.annotation, "annotation"),
            (.const, "const"),
            (.crossinline, "crossinline"),
            (.lateinit, "lateinit"),
            (.noinline, "noinline"),
            (.tailrec, "tailrec"),
            (.vararg, "vararg"),
            (.value, "value"),
        ]

        for (keyword, expected) in expectedKeywords {
            XCTAssertEqual(keyword.rawValue, expected, "Keyword.\(expected) rawValue mismatch")
        }
    }

    func testKeywordInitFromRawValueRoundTrips() {
        let allRawValues = [
            "as", "break", "class", "catch", "continue", "data", "do", "else",
            "false", "dynamic", "enum", "external", "for", "fun", "if", "infix",
            "in", "is", "import", "interface", "finally", "null", "operator",
            "object", "package", "return", "super", "this", "typealias", "throw",
            "true", "try", "val", "var", "while", "when", "sealed", "inner",
            "reified", "open", "private", "public", "protected", "internal",
            "override", "final", "abstract", "suspend", "inline", "expect",
            "actual", "constructor", "companion", "annotation", "const",
            "crossinline", "lateinit", "noinline", "tailrec", "vararg", "value",
        ]

        for raw in allRawValues {
            let keyword = Keyword(rawValue: raw)
            XCTAssertNotNil(keyword, "Keyword(rawValue: \"\(raw)\") should not be nil")
            XCTAssertEqual(keyword?.rawValue, raw)
        }
    }

    func testKeywordInitFromInvalidRawValueReturnsNil() {
        XCTAssertNil(Keyword(rawValue: "notAKeyword"))
        XCTAssertNil(Keyword(rawValue: ""))
        XCTAssertNil(Keyword(rawValue: "FUN"))
    }

    func testKeywordTokenKindEquality() {
        let allKeywords: [Keyword] = [
            .as, .break, .class, .catch, .continue, .data, .do, .else,
            .false, .dynamic, .enum, .external, .for, .fun, .if, .infix,
            .in, .is, .import, .interface, .finally, .null, .operator,
            .object, .package, .return, .super, .this, .typealias, .throw,
            .true, .try, .val, .var, .while, .when, .sealed, .inner,
            .reified, .open, .private, .public, .protected, .internal,
            .override, .final, .abstract, .suspend, .inline, .expect,
            .actual, .constructor, .companion, .annotation, .const,
            .crossinline, .lateinit, .noinline, .tailrec, .vararg, .value,
        ]

        for keyword in allKeywords {
            let kind = TokenKind.keyword(keyword)
            XCTAssertEqual(kind, TokenKind.keyword(keyword))
        }

        // Different keywords should not be equal
        XCTAssertNotEqual(TokenKind.keyword(.fun), TokenKind.keyword(.val))
        XCTAssertNotEqual(TokenKind.keyword(.class), TokenKind.keyword(.interface))
    }

    // MARK: - SoftKeyword enum: all cases

    func testSoftKeywordAllCasesRawValues() {
        let expectedSoftKeywords: [(SoftKeyword, String)] = [
            (.by, "by"),
            (.get, "get"),
            (.set, "set"),
            (.field, "field"),
            (.property, "property"),
            (.receiver, "receiver"),
            (.param, "param"),
            (.setparam, "setparam"),
            (.delegate, "delegate"),
            (.file, "file"),
            (.where, "where"),
            (.`init`, "init"),
            (.constructor, "constructor"),
            (.out, "out"),
            (.when, "when"),
        ]

        for (softKeyword, expected) in expectedSoftKeywords {
            XCTAssertEqual(softKeyword.rawValue, expected, "SoftKeyword.\(expected) rawValue mismatch")
        }
    }

    func testSoftKeywordInitFromRawValueRoundTrips() {
        let allRawValues = [
            "by", "get", "set", "field", "property", "receiver",
            "param", "setparam", "delegate", "file", "where",
            "init", "constructor", "out", "when",
        ]

        for raw in allRawValues {
            let softKeyword = SoftKeyword(rawValue: raw)
            XCTAssertNotNil(softKeyword, "SoftKeyword(rawValue: \"\(raw)\") should not be nil")
            XCTAssertEqual(softKeyword?.rawValue, raw)
        }
    }

    func testSoftKeywordInitFromInvalidRawValueReturnsNil() {
        XCTAssertNil(SoftKeyword(rawValue: "notASoftKeyword"))
        XCTAssertNil(SoftKeyword(rawValue: ""))
        XCTAssertNil(SoftKeyword(rawValue: "GET"))
    }

    func testSoftKeywordTokenKindEquality() {
        let allSoftKeywords: [SoftKeyword] = [
            .by, .get, .set, .field, .property, .receiver,
            .param, .setparam, .delegate, .file, .where,
            .`init`, .constructor, .out, .when,
        ]

        for softKeyword in allSoftKeywords {
            let kind = TokenKind.softKeyword(softKeyword)
            XCTAssertEqual(kind, TokenKind.softKeyword(softKeyword))
        }

        // Different soft keywords should not be equal
        XCTAssertNotEqual(TokenKind.softKeyword(.get), TokenKind.softKeyword(.set))
        XCTAssertNotEqual(TokenKind.softKeyword(.field), TokenKind.softKeyword(.property))
    }

    // MARK: - Symbol enum: all cases

    func testSymbolAllCasesRawValues() {
        let expectedSymbols: [(Symbol, String)] = [
            (.plus, "+"),
            (.minus, "-"),
            (.star, "*"),
            (.slash, "/"),
            (.percent, "%"),
            (.plusPlus, "++"),
            (.minusMinus, "--"),
            (.ampAmp, "&&"),
            (.barBar, "||"),
            (.bang, "!"),
            (.equalEqual, "=="),
            (.bangEqual, "!="),
            (.lessThan, "<"),
            (.lessOrEqual, "<="),
            (.greaterThan, ">"),
            (.greaterOrEqual, ">="),
            (.assign, "="),
            (.plusAssign, "+="),
            (.minusAssign, "-="),
            (.starAssign, "*="),
            (.slashAssign, "/="),
            (.percentAssign, "%="),
            (.dotDot, ".."),
            (.dotDotLt, "..<"),
            (.questionQuestion, "??"),
            (.question, "?"),
            (.questionDot, "?."),
            (.questionColon, "?:"),
            (.bangBang, "!!"),
            (.doubleColon, "::"),
            (.comma, ","),
            (.dot, "."),
            (.semicolon, ";"),
            (.colon, ":"),
            (.arrow, "->"),
            (.fatArrow, "=>"),
            (.lParen, "("),
            (.rParen, ")"),
            (.lBracket, "["),
            (.rBracket, "]"),
            (.lBrace, "{"),
            (.rBrace, "}"),
            (.at, "@"),
            (.hash, "#"),
        ]

        for (symbol, expected) in expectedSymbols {
            XCTAssertEqual(symbol.rawValue, expected, "Symbol.\(symbol) rawValue mismatch")
        }
    }

    func testSymbolInitFromRawValueRoundTrips() {
        let allRawValues = [
            "+", "-", "*", "/", "%", "++", "--", "&&", "||", "!",
            "==", "!=", "<", "<=", ">", ">=", "=", "+=", "-=", "*=",
            "/=", "%=", "..", "..<", "??", "?", "?.", "?:", "!!",
            "::", ",", ".", ";", ":", "->", "=>", "(", ")", "[", "]",
            "{", "}", "@", "#",
        ]

        for raw in allRawValues {
            let symbol = Symbol(rawValue: raw)
            XCTAssertNotNil(symbol, "Symbol(rawValue: \"\(raw)\") should not be nil")
            XCTAssertEqual(symbol?.rawValue, raw)
        }
    }

    func testSymbolInitFromInvalidRawValueReturnsNil() {
        XCTAssertNil(Symbol(rawValue: "notASymbol"))
        XCTAssertNil(Symbol(rawValue: ""))
        XCTAssertNil(Symbol(rawValue: "+++"))
    }

    func testSymbolTokenKindEquality() {
        let allSymbols: [Symbol] = [
            .plus, .minus, .star, .slash, .percent, .plusPlus, .minusMinus,
            .ampAmp, .barBar, .bang, .equalEqual, .bangEqual, .lessThan,
            .lessOrEqual, .greaterThan, .greaterOrEqual, .assign, .plusAssign,
            .minusAssign, .starAssign, .slashAssign, .percentAssign, .dotDot,
            .dotDotLt, .questionQuestion, .question, .questionDot, .questionColon,
            .bangBang, .doubleColon, .comma, .dot, .semicolon, .colon, .arrow,
            .fatArrow, .lParen, .rParen, .lBracket, .rBracket, .lBrace, .rBrace,
            .at, .hash,
        ]

        for symbol in allSymbols {
            let kind = TokenKind.symbol(symbol)
            XCTAssertEqual(kind, TokenKind.symbol(symbol))
        }

        // Different symbols should not be equal
        XCTAssertNotEqual(TokenKind.symbol(.plus), TokenKind.symbol(.minus))
        XCTAssertNotEqual(TokenKind.symbol(.lParen), TokenKind.symbol(.rParen))
    }

    // MARK: - TokenKind: all variants

    func testTokenKindLongLiteral() {
        let kind = TokenKind.longLiteral("42L")
        XCTAssertEqual(kind, TokenKind.longLiteral("42L"))
        XCTAssertNotEqual(kind, TokenKind.longLiteral("0L"))
        XCTAssertNotEqual(kind, TokenKind.intLiteral("42"))
    }

    func testTokenKindFloatLiteral() {
        let kind = TokenKind.floatLiteral("3.14f")
        XCTAssertEqual(kind, TokenKind.floatLiteral("3.14f"))
        XCTAssertNotEqual(kind, TokenKind.floatLiteral("2.71f"))
        XCTAssertNotEqual(kind, TokenKind.doubleLiteral("3.14"))
    }

    func testTokenKindDoubleLiteral() {
        let kind = TokenKind.doubleLiteral("3.14")
        XCTAssertEqual(kind, TokenKind.doubleLiteral("3.14"))
        XCTAssertNotEqual(kind, TokenKind.doubleLiteral("2.71"))
        XCTAssertNotEqual(kind, TokenKind.floatLiteral("3.14f"))
    }

    func testTokenKindStringQuote() {
        let kind = TokenKind.stringQuote
        XCTAssertEqual(kind, TokenKind.stringQuote)
        XCTAssertNotEqual(kind, TokenKind.rawStringQuote)
    }

    func testTokenKindRawStringQuote() {
        let kind = TokenKind.rawStringQuote
        XCTAssertEqual(kind, TokenKind.rawStringQuote)
        XCTAssertNotEqual(kind, TokenKind.stringQuote)
    }

    func testTokenKindTemplateExprStart() {
        let kind = TokenKind.templateExprStart
        XCTAssertEqual(kind, TokenKind.templateExprStart)
        XCTAssertNotEqual(kind, TokenKind.templateExprEnd)
    }

    func testTokenKindTemplateExprEnd() {
        let kind = TokenKind.templateExprEnd
        XCTAssertEqual(kind, TokenKind.templateExprEnd)
        XCTAssertNotEqual(kind, TokenKind.templateExprStart)
    }

    func testTokenKindTemplateSimpleNameStart() {
        let kind = TokenKind.templateSimpleNameStart
        XCTAssertEqual(kind, TokenKind.templateSimpleNameStart)
        XCTAssertNotEqual(kind, TokenKind.templateExprStart)
        XCTAssertNotEqual(kind, TokenKind.templateExprEnd)
    }

    func testTokenKindIntLiteral() {
        let kind = TokenKind.intLiteral("42")
        XCTAssertEqual(kind, TokenKind.intLiteral("42"))
        XCTAssertNotEqual(kind, TokenKind.intLiteral("0"))
        XCTAssertNotEqual(kind, TokenKind.longLiteral("42L"))
    }

    func testTokenKindIdentifier() {
        let interner = StringInterner()
        let id = interner.intern("myVar")
        let kind = TokenKind.identifier(id)
        XCTAssertEqual(kind, TokenKind.identifier(id))

        let otherId = interner.intern("otherVar")
        XCTAssertNotEqual(kind, TokenKind.identifier(otherId))
        XCTAssertNotEqual(kind, TokenKind.backtickedIdentifier(id))
    }

    func testTokenKindStringSegment() {
        let interner = StringInterner()
        let seg = interner.intern("hello world")
        let kind = TokenKind.stringSegment(seg)
        XCTAssertEqual(kind, TokenKind.stringSegment(seg))

        let otherSeg = interner.intern("other")
        XCTAssertNotEqual(kind, TokenKind.stringSegment(otherSeg))
    }

    func testTokenKindEof() {
        let kind = TokenKind.eof
        XCTAssertEqual(kind, TokenKind.eof)
        XCTAssertNotEqual(kind, TokenKind.stringQuote)
    }

    func testTokenKindMissingVariant() {
        let missing1 = TokenKind.missing(expected: .keyword(.val))
        let missing2 = TokenKind.missing(expected: .keyword(.val))
        let missing3 = TokenKind.missing(expected: .keyword(.var))

        XCTAssertEqual(missing1, missing2)
        XCTAssertNotEqual(missing1, missing3)
        XCTAssertNotEqual(missing1, TokenKind.keyword(.val))

        // missing with symbol
        let missingSymbol = TokenKind.missing(expected: .symbol(.lParen))
        XCTAssertEqual(missingSymbol, TokenKind.missing(expected: .symbol(.lParen)))
        XCTAssertNotEqual(missingSymbol, TokenKind.missing(expected: .symbol(.rParen)))

        // missing with eof
        let missingEof = TokenKind.missing(expected: .eof)
        XCTAssertEqual(missingEof, TokenKind.missing(expected: .eof))
    }

    func testTokenKindCharLiteral() {
        let kind = TokenKind.charLiteral(0x41)
        XCTAssertEqual(kind, TokenKind.charLiteral(0x41))
        XCTAssertNotEqual(kind, TokenKind.charLiteral(0x42))
        XCTAssertNotEqual(kind, TokenKind.intLiteral("65"))
    }

    func testTokenKindAllVariantsAreMutuallyDistinct() {
        let interner = StringInterner()
        let id = interner.intern("x")

        let allKinds: [TokenKind] = [
            .identifier(id),
            .backtickedIdentifier(id),
            .keyword(.fun),
            .softKeyword(.get),
            .intLiteral("1"),
            .longLiteral("1L"),
            .floatLiteral("1.0f"),
            .doubleLiteral("1.0"),
            .charLiteral(65),
            .stringSegment(id),
            .stringQuote,
            .rawStringQuote,
            .templateExprStart,
            .templateExprEnd,
            .templateSimpleNameStart,
            .symbol(.plus),
            .eof,
            .missing(expected: .eof),
        ]

        // Each kind should only be equal to itself
        for i in 0..<allKinds.count {
            for j in 0..<allKinds.count {
                if i == j {
                    XCTAssertEqual(allKinds[i], allKinds[j], "TokenKind at index \(i) should equal itself")
                } else {
                    XCTAssertNotEqual(allKinds[i], allKinds[j], "TokenKind at index \(i) should not equal index \(j)")
                }
            }
        }
    }
}
