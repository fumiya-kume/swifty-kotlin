@testable import CompilerCore
import XCTest

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
        guard case let .backtickedIdentifier(name) = backticked.kind else {
            return XCTFail("Expected backtickedIdentifier")
        }
        XCTAssertEqual(interner.resolve(name), "myFun")

        let charLit = Token(kind: .charLiteral(65), range: range)
        guard case let .charLiteral(code) = charLit.kind else {
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
            (.value, "value")
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
            "crossinline", "lateinit", "noinline", "tailrec", "vararg", "value"
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
            .crossinline, .lateinit, .noinline, .tailrec, .vararg, .value
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
            (.when, "when")
        ]

        for (softKeyword, expected) in expectedSoftKeywords {
            XCTAssertEqual(softKeyword.rawValue, expected, "SoftKeyword.\(expected) rawValue mismatch")
        }
    }

    func testSoftKeywordInitFromRawValueRoundTrips() {
        let allRawValues = [
            "by", "get", "set", "field", "property", "receiver",
            "param", "setparam", "delegate", "file", "where",
            "init", "constructor", "out", "when"
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
            .`init`, .constructor, .out, .when
        ]

        for softKeyword in allSoftKeywords {
            let kind = TokenKind.softKeyword(softKeyword)
            XCTAssertEqual(kind, TokenKind.softKeyword(softKeyword))
        }

        // Different soft keywords should not be equal
        XCTAssertNotEqual(TokenKind.softKeyword(.get), TokenKind.softKeyword(.set))
        XCTAssertNotEqual(TokenKind.softKeyword(.field), TokenKind.softKeyword(.property))
    }
}
