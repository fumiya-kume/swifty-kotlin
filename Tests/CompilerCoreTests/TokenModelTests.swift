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
}
