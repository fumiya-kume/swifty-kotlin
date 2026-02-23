import XCTest
@testable import CompilerCore

final class SourceLocationTests: XCTestCase {

    // MARK: - TokenID

    func testTokenIDDefaultIsInvalid() {
        let id = TokenID()
        XCTAssertEqual(id, TokenID.invalid)
        XCTAssertEqual(id.rawValue, -1)
    }

    func testTokenIDWithRawValue() {
        let id = TokenID(rawValue: 42)
        XCTAssertEqual(id.rawValue, 42)
    }

    func testTokenIDEquality() {
        let a = TokenID(rawValue: 5)
        let b = TokenID(rawValue: 5)
        let c = TokenID(rawValue: 6)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testTokenIDHashable() {
        let a = TokenID(rawValue: 10)
        let b = TokenID(rawValue: 10)
        var set = Set<TokenID>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
    }

    func testTokenIDZero() {
        let id = TokenID(rawValue: 0)
        XCTAssertEqual(id.rawValue, 0)
        XCTAssertNotEqual(id, TokenID.invalid)
    }

    // MARK: - NodeID

    func testNodeIDDefaultIsInvalid() {
        let id = NodeID()
        XCTAssertEqual(id, NodeID.invalid)
        XCTAssertEqual(id.rawValue, -1)
    }

    func testNodeIDWithRawValue() {
        let id = NodeID(rawValue: 99)
        XCTAssertEqual(id.rawValue, 99)
    }

    func testNodeIDEquality() {
        let a = NodeID(rawValue: 3)
        let b = NodeID(rawValue: 3)
        let c = NodeID(rawValue: 4)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testNodeIDHashable() {
        let a = NodeID(rawValue: 7)
        let b = NodeID(rawValue: 7)
        var set = Set<NodeID>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - DeclID

    func testDeclIDDefaultIsInvalid() {
        let id = DeclID()
        XCTAssertEqual(id, DeclID.invalid)
        XCTAssertEqual(id.rawValue, -1)
    }

    func testDeclIDWithRawValue() {
        let id = DeclID(rawValue: 100)
        XCTAssertEqual(id.rawValue, 100)
    }

    func testDeclIDEquality() {
        let a = DeclID(rawValue: 1)
        let b = DeclID(rawValue: 1)
        let c = DeclID(rawValue: 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testDeclIDHashable() {
        let a = DeclID(rawValue: 50)
        let b = DeclID(rawValue: 50)
        var set = Set<DeclID>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - FileID

    func testFileIDDefaultIsInvalid() {
        let id = FileID()
        XCTAssertEqual(id, FileID.invalid)
        XCTAssertEqual(id.rawValue, -1)
    }

    func testFileIDWithInt32RawValue() {
        let id = FileID(rawValue: Int32(25))
        XCTAssertEqual(id.rawValue, 25)
    }

    func testFileIDWithIntRawValue() {
        let id = FileID(rawValue: 30)
        XCTAssertEqual(id.rawValue, 30)
    }

    func testFileIDEquality() {
        let a = FileID(rawValue: 10)
        let b = FileID(rawValue: 10)
        let c = FileID(rawValue: 11)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testFileIDHashable() {
        let a = FileID(rawValue: 20)
        let b = FileID(rawValue: 20)
        var set = Set<FileID>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - SourceLocation

    func testSourceLocationInit() {
        let loc = SourceLocation(file: FileID(rawValue: 1), offset: 42)
        XCTAssertEqual(loc.file, FileID(rawValue: 1))
        XCTAssertEqual(loc.offset, 42)
    }

    func testSourceLocationEquality() {
        let a = SourceLocation(file: FileID(rawValue: 1), offset: 10)
        let b = SourceLocation(file: FileID(rawValue: 1), offset: 10)
        let c = SourceLocation(file: FileID(rawValue: 2), offset: 10)
        let d = SourceLocation(file: FileID(rawValue: 1), offset: 20)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
    }

    // MARK: - SourceRange

    func testSourceRangeInit() {
        let start = SourceLocation(file: FileID(rawValue: 0), offset: 0)
        let end = SourceLocation(file: FileID(rawValue: 0), offset: 10)
        let range = SourceRange(start: start, end: end)
        XCTAssertEqual(range.start, start)
        XCTAssertEqual(range.end, end)
    }

    func testSourceRangeEquality() {
        let r1 = makeRange(file: FileID(rawValue: 0), start: 0, end: 5)
        let r2 = makeRange(file: FileID(rawValue: 0), start: 0, end: 5)
        let r3 = makeRange(file: FileID(rawValue: 0), start: 0, end: 10)
        XCTAssertEqual(r1, r2)
        XCTAssertNotEqual(r1, r3)
    }

    // MARK: - LineColumn

    func testLineColumnInit() {
        let lc = LineColumn(line: 5, column: 10)
        XCTAssertEqual(lc.line, 5)
        XCTAssertEqual(lc.column, 10)
    }

    func testLineColumnEquality() {
        let a = LineColumn(line: 1, column: 1)
        let b = LineColumn(line: 1, column: 1)
        let c = LineColumn(line: 2, column: 1)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - ASTNodeID

    func testASTNodeIDDefaultIsInvalid() {
        let id = ASTNodeID()
        XCTAssertEqual(id, ASTNodeID.invalid)
        XCTAssertEqual(id.rawValue, -1)
    }

    func testASTNodeIDWithRawValue() {
        let id = ASTNodeID(rawValue: 77)
        XCTAssertEqual(id.rawValue, 77)
    }

    func testASTNodeIDEquality() {
        let a = ASTNodeID(rawValue: 5)
        let b = ASTNodeID(rawValue: 5)
        let c = ASTNodeID(rawValue: 6)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testASTNodeIDHashable() {
        let a = ASTNodeID(rawValue: 12)
        let b = ASTNodeID(rawValue: 12)
        var set = Set<ASTNodeID>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - ExprID

    func testExprIDDefaultIsInvalid() {
        let id = ExprID()
        XCTAssertEqual(id, ExprID.invalid)
        XCTAssertEqual(id.rawValue, -1)
    }

    func testExprIDWithRawValue() {
        let id = ExprID(rawValue: 33)
        XCTAssertEqual(id.rawValue, 33)
    }

    func testExprIDEquality() {
        let a = ExprID(rawValue: 8)
        let b = ExprID(rawValue: 8)
        let c = ExprID(rawValue: 9)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - TypeRefID

    func testTypeRefIDDefaultIsInvalid() {
        let id = TypeRefID()
        XCTAssertEqual(id, TypeRefID.invalid)
        XCTAssertEqual(id.rawValue, -1)
    }

    func testTypeRefIDWithRawValue() {
        let id = TypeRefID(rawValue: 55)
        XCTAssertEqual(id.rawValue, 55)
    }

    func testTypeRefIDEquality() {
        let a = TypeRefID(rawValue: 14)
        let b = TypeRefID(rawValue: 14)
        let c = TypeRefID(rawValue: 15)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

}
