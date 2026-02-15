import XCTest
@testable import CompilerCore

final class SyntaxArenaTests: XCTestCase {
    func testAppendTokenAndMakeNodeRoundTrip() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let tokenA = makeToken(kind: .identifier(interner.intern("a")), start: 0, end: 1)
        let tokenB = makeToken(kind: .identifier(interner.intern("b")), start: 2, end: 3)
        let tokenIDA = arena.appendToken(tokenA)
        let tokenIDB = arena.appendToken(tokenB)

        XCTAssertEqual(tokenIDA, TokenID(rawValue: 0))
        XCTAssertEqual(tokenIDB, TokenID(rawValue: 1))

        let range = makeRange(start: 0, end: 3)
        let nodeID = arena.makeNode(kind: .callExpr, range: range, [.token(tokenIDA), .token(tokenIDB)])
        let node = arena.node(nodeID)

        XCTAssertEqual(node.kind, .callExpr)
        XCTAssertEqual(node.range, range)
        XCTAssertEqual(node.firstChildIndex, 0)
        XCTAssertEqual(node.childCount, 2)

        XCTAssertEqual(Array(arena.children(of: nodeID)), [.token(tokenIDA), .token(tokenIDB)])
    }

    func testNodeReturnsSentinelForInvalidIDs() {
        let arena = SyntaxArena()

        let negative = arena.node(NodeID(rawValue: -1))
        XCTAssertEqual(negative.kind, .statement)
        XCTAssertEqual(negative.range.start.file.rawValue, invalidID)
        XCTAssertEqual(negative.childCount, 0)

        let tooLarge = arena.node(NodeID(rawValue: 999))
        XCTAssertEqual(tooLarge.kind, .statement)
        XCTAssertEqual(tooLarge.range.end.file.rawValue, invalidID)
    }

    func testChildrenReturnsEmptyForNodesWithoutAddressableChildren() {
        let arena = SyntaxArena()
        let emptyNode = arena.makeNode(kind: .block, range: makeRange(), [])

        XCTAssertEqual(Array(arena.children(of: emptyNode)), [])
        XCTAssertEqual(Array(arena.children(of: NodeID(rawValue: 1234))), [])
    }
}
