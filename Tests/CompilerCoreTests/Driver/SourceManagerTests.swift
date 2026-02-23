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

    func testLineColumnReturnsDefaultForEmptyFile() {
        let manager = SourceManager()
        let id = manager.addFile(path: "empty.kt", contents: Data())
        let loc = SourceLocation(file: id, offset: 0)
        XCTAssertEqual(manager.lineColumn(of: loc), LineColumn(line: 1, column: 1))
    }

    func testAddFileByPathThrowsForNonExistentFile() {
        let manager = SourceManager()
        XCTAssertThrowsError(try manager.addFile(path: "/non/existent/file.kt"))
    }

    func testNegativeFileIDUsesSafeFallbacks() {
        let manager = SourceManager()
        let negativeID = FileID(rawValue: -1)
        XCTAssertEqual(manager.contents(of: negativeID), Data())
        XCTAssertEqual(manager.path(of: negativeID), "")
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

    // MARK: - Additional Coverage

    func testFileIDsOrderingWithMultipleFiles() {
        let manager = SourceManager()
        let id0 = manager.addFile(path: "first.kt", contents: Data("a".utf8))
        let id1 = manager.addFile(path: "second.kt", contents: Data("b".utf8))
        let id2 = manager.addFile(path: "third.kt", contents: Data("c".utf8))

        let ids = manager.fileIDs()
        XCTAssertEqual(ids, [id0, id1, id2], "fileIDs() should return IDs in insertion order")
        XCTAssertEqual(ids.count, 3)

        // Verify each ID maps back to the correct path
        XCTAssertEqual(manager.path(of: ids[0]), "first.kt")
        XCTAssertEqual(manager.path(of: ids[1]), "second.kt")
        XCTAssertEqual(manager.path(of: ids[2]), "third.kt")
    }

    func testSliceWithSameStartAndEndReturnsEmpty() {
        let manager = SourceManager()
        let id = manager.addFile(path: "empty-slice.kt", contents: Data("hello".utf8))

        // start == end at various positions should always yield an empty slice
        for offset in [0, 1, 3, 5] {
            let slice = manager.slice(makeRange(file: id, start: offset, end: offset))
            XCTAssertEqual(String(slice), "", "slice with start == end at offset \(offset) should be empty")
        }
    }

    func testSliceSpanningMultipleLines() {
        let manager = SourceManager()
        let source = "line1\nline2\nline3\n"
        let id = manager.addFile(path: "multiline.kt", contents: Data(source.utf8))

        // Slice spanning from the middle of line1 into line2
        // "ine1\nli" -> offsets 1..<8
        let sliceA = manager.slice(makeRange(file: id, start: 1, end: 8))
        XCTAssertEqual(String(sliceA), "ine1\nli")

        // Slice spanning all three lines
        let sliceB = manager.slice(makeRange(file: id, start: 0, end: 18))
        XCTAssertEqual(String(sliceB), source)

        // Slice spanning from line2 into line3
        // "line2\nline3\n" -> offsets 6..<18
        let sliceC = manager.slice(makeRange(file: id, start: 6, end: 18))
        XCTAssertEqual(String(sliceC), "line2\nline3\n")
    }

    func testLineColumnWithUnicodeAcrossMultipleLines() {
        let manager = SourceManager()
        // Line 1: "café\n"  (UTF-8: c=1, a=1, f=1, é=2, \n=1 → 6 bytes)
        // Line 2: "日本語\n" (UTF-8: 日=3, 本=3, 語=3, \n=1 → 10 bytes)
        // Line 3: "ok"     (UTF-8: o=1, k=1 → 2 bytes)
        let source = "café\n日本語\nok"
        let id = manager.addFile(path: "unicode-multiline.kt", contents: Data(source.utf8))

        // Offset 0 → Line 1, Column 1 (start of "café")
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 0)),
            LineColumn(line: 1, column: 1)
        )

        // Offset 3 → Line 1, Column 4 (before 'é', after "caf")
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 3)),
            LineColumn(line: 1, column: 4)
        )

        // Offset 5 → Line 1, Column 5 (after 'é' which is 2 UTF-8 bytes, before '\n')
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 5)),
            LineColumn(line: 1, column: 5)
        )

        // Offset 6 → Line 2, Column 1 (start of "日本語")
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 6)),
            LineColumn(line: 2, column: 1)
        )

        // Offset 9 → Line 2, Column 2 (after "日", which is 3 UTF-8 bytes)
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 9)),
            LineColumn(line: 2, column: 2)
        )

        // Offset 12 → Line 2, Column 3 (after "日本")
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 12)),
            LineColumn(line: 2, column: 3)
        )

        // Offset 15 → Line 2, Column 4 (after "日本語", before '\n')
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 15)),
            LineColumn(line: 2, column: 4)
        )

        // Offset 16 → Line 3, Column 1 (start of "ok")
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 16)),
            LineColumn(line: 3, column: 1)
        )

        // Offset 17 → Line 3, Column 2 (after "o")
        XCTAssertEqual(
            manager.lineColumn(of: SourceLocation(file: id, offset: 17)),
            LineColumn(line: 3, column: 2)
        )
    }
}
