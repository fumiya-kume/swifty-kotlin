import XCTest
@testable import CompilerCore

final class TokenStreamTests: XCTestCase {
    func testPeekReturnsSyntheticEOFForEmptyStreamAndNegativeOffset() {
        let stream = TokenStream([])

        XCTAssertEqual(stream.peek().kind, .eof)
        XCTAssertEqual(stream.peek(-1).kind, .eof)
    }

    func testPeekReturnsInRangeTokenAndEOFForOutOfRange() {
        let interner = StringInterner()
        let first = makeToken(kind: .identifier(interner.intern("first")))
        let second = makeToken(kind: .identifier(interner.intern("second")), start: 1, end: 2)
        let stream = TokenStream([first, second])

        XCTAssertEqual(stream.peek(0), first)
        XCTAssertEqual(stream.peek(1), second)
        XCTAssertEqual(stream.peek(2).kind, .eof)
    }

    func testAdvanceStopsAtEndWithoutOverflowingIndex() {
        let token = makeToken(kind: .keyword(.fun))
        let stream = TokenStream([token])

        XCTAssertEqual(stream.advance(), token)
        XCTAssertEqual(stream.index, 1)
        XCTAssertEqual(stream.advance().kind, .eof)
        XCTAssertEqual(stream.index, 1)
    }

    func testAtEOFReflectsCurrentCursorState() {
        let nonEmpty = TokenStream([makeToken(kind: .keyword(.if))])
        XCTAssertFalse(nonEmpty.atEOF())
        _ = nonEmpty.advance()
        XCTAssertTrue(nonEmpty.atEOF())

        let empty = TokenStream([])
        XCTAssertTrue(empty.atEOF())
    }

    func testConsumeIfConsumesOnlyWhenPredicateMatches() {
        let interner = StringInterner()
        let first = makeToken(kind: .identifier(interner.intern("x")))
        let second = makeToken(kind: .symbol(.plus), start: 1, end: 2)
        let stream = TokenStream([first, second])

        let consumed = stream.consumeIf { token in
            if case .identifier = token.kind { return true }
            return false
        }
        XCTAssertEqual(consumed, first)
        XCTAssertEqual(stream.index, 1)

        let notConsumed = stream.consumeIf { token in
            if case .keyword = token.kind { return true }
            return false
        }
        XCTAssertNil(notConsumed)
        XCTAssertEqual(stream.index, 1)
    }

    // MARK: - Additional Coverage

    func testPeekConsecutivePositiveOffsetsOutOfRange() {
        let interner = StringInterner()
        let token = makeToken(kind: .identifier(interner.intern("only")))
        let stream = TokenStream([token])

        // offset 0 is valid
        XCTAssertEqual(stream.peek(0), token)
        // offsets 1..5 are all out of range → synthetic EOF
        for offset in 1...5 {
            XCTAssertEqual(stream.peek(offset).kind, .eof,
                           "peek(\(offset)) should return EOF for a single-element stream")
        }
    }

    func testConsecutiveAdvanceOnEmptyStream() {
        let stream = TokenStream([])

        // Calling advance() repeatedly on an empty stream should always
        // return synthetic EOF and never move the index past 0.
        for _ in 0..<5 {
            let token = stream.advance()
            XCTAssertEqual(token.kind, .eof)
            XCTAssertEqual(stream.index, 0)
        }
    }

    func testConsumeIfPredicateCanAccessTokenDetails() {
        let interner = StringInterner()
        let id = makeToken(kind: .identifier(interner.intern("hello")))
        let plus = makeToken(kind: .symbol(.plus), start: 5, end: 6)
        let num = makeToken(kind: .intLiteral("42"), start: 6, end: 8)
        let stream = TokenStream([id, plus, num])

        // Complex predicate: identifier AND the interned name resolves to "hello"
        let matched = stream.consumeIf { token in
            if case .identifier(let interned) = token.kind {
                return interner.resolve(interned) == "hello"
            }
            return false
        }
        XCTAssertEqual(matched, id)
        XCTAssertEqual(stream.index, 1)

        // Complex predicate: symbol that is either plus or minus
        let matchedSymbol = stream.consumeIf { token in
            if case .symbol(let sym) = token.kind {
                return sym == .plus || sym == .minus
            }
            return false
        }
        XCTAssertEqual(matchedSymbol, plus)
        XCTAssertEqual(stream.index, 2)

        // Complex predicate that does NOT match: intLiteral with value > 100
        let noMatch = stream.consumeIf { token in
            if case .intLiteral(let value) = token.kind,
               let intValue = Int(value) {
                return intValue > 100
            }
            return false
        }
        XCTAssertNil(noMatch)
        XCTAssertEqual(stream.index, 2)
    }
}
