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
}
