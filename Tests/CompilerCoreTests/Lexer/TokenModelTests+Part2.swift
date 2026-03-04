@testable import CompilerCore
import XCTest

extension TokenModelTests {
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
            (.hash, "#")
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
            "{", "}", "@", "#"
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
            .at, .hash
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
            .missing(expected: .eof)
        ]

        // Each kind should only be equal to itself
        for i in 0 ..< allKinds.count {
            for j in 0 ..< allKinds.count {
                if i == j {
                    XCTAssertEqual(allKinds[i], allKinds[j], "TokenKind at index \(i) should equal itself")
                } else {
                    XCTAssertNotEqual(allKinds[i], allKinds[j], "TokenKind at index \(i) should not equal index \(j)")
                }
            }
        }
    }
}
