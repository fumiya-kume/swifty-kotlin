import Foundation
import XCTest
@testable import CompilerCore

final class SourceManagerTests: XCTestCase {
    func testAddFileAndLookupByIDAndEnumeration() {
        let manager = SourceManager()
        let id = manager.addFile(path: "in-memory.kt", contents: Data("line1\nline2".utf8))

        XCTAssertEqual(manager.path(of: id), "in-memory.kt")
        XCTAssertEqual(String(decoding: manager.contents(of: id), as: UTF8.self), "line1\nline2")
        XCTAssertEqual(manager.fileCount, 1)
        XCTAssertEqual(manager.fileIDs(), [id])
    }

    func testAddFileByPathLoadsContents() throws {
        let manager = SourceManager()

        try withTemporaryFile(contents: "abc") { path in
            let id = try manager.addFile(path: path)
            XCTAssertEqual(manager.path(of: id), path)
            XCTAssertEqual(String(decoding: manager.contents(of: id), as: UTF8.self), "abc")
        }
    }

    func testInvalidFileIDUsesSafeFallbacks() {
        let manager = SourceManager()
        let invalid = FileID(rawValue: 999)

        XCTAssertEqual(manager.contents(of: invalid), Data())
        XCTAssertEqual(manager.path(of: invalid), "")

        let loc = SourceLocation(file: invalid, offset: 10)
        XCTAssertEqual(manager.lineColumn(of: loc), LineColumn(line: 1, column: 1))

        let slice = manager.slice(makeRange(file: invalid, start: 0, end: 10))
        XCTAssertEqual(String(slice), "")
    }

    func testLineColumnClampsOffsetsAndHandlesUnicode() {
        let manager = SourceManager()
        let id = manager.addFile(path: "unicode.kt", contents: Data("a\néx\n".utf8))

        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: -10)),
            LineColumn(line: 1, column: 1)
        )
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 1)),
            LineColumn(line: 1, column: 2)
        )
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 2)),
            LineColumn(line: 2, column: 1)
        )
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 5)),
            LineColumn(line: 2, column: 3)
        )
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 6)),
            LineColumn(line: 3, column: 1)
        )
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 100)),
            LineColumn(line: 3, column: 1)
        )
    }

    func testSliceClampsBoundsAndNormalizesInvertedRanges() {
        let manager = SourceManager()
        let id = manager.addFile(path: "slice.kt", contents: Data("abcdef".utf8))

        let sliceA = manager.slice(makeRange(file: id, start: -3, end: 3))
        XCTAssertEqual(String(sliceA), "abc")

        let sliceB = manager.slice(makeRange(file: id, start: 4, end: 2))
        XCTAssertEqual(String(sliceB), "")

        let sliceC = manager.slice(makeRange(file: id, start: 2, end: 99))
        XCTAssertEqual(String(sliceC), "cdef")
    }
}
