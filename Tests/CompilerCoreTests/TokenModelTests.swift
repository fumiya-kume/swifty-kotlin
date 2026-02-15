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
