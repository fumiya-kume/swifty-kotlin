import Foundation
@testable import Runtime
import XCTest

// MARK: - STDLIB-IO-FN-040 lambda thunks for useLines
//
// Block receives the materialised lines as a boxed Int (RuntimeListBox raw pointer).
// We unbox the list, read its size, and box the count back as an Int — matching the
// collection HOF lambda ABI consumed by `runtimeInvokeCollectionLambda1`.

// MARK: - STDLIB-IO-FN-017 lambda thunks for forEachLine
//
// Action receives each line as a raw String pointer (boxed Int). We extract the
// Swift String value and accumulate it into `forEachLineCollectedLines` so tests
// can assert which lines were visited.

nonisolated(unsafe) private var forEachLineCollectedLines: [String] = []

private let forEachLineCollector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lineRaw, outThrown in
    outThrown?.pointee = 0
    if let str = extractString(from: UnsafeMutableRawPointer(bitPattern: lineRaw)) {
        forEachLineCollectedLines.append(str)
    }
    return 0
}

private let forEachLineAlwaysThrows: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "ActionError: forEachLine action threw")
    return 0
}

private let useLinesCountsLines: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, outThrown in
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: value),
          let list = tryCast(ptr, to: RuntimeListBox.self)
    else {
        return kk_box_int(-1)
    }
    return kk_box_int(list.elements.count)
}

private let useLinesAlwaysThrows: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "BlockError: useLines lambda threw")
    return 0
}

private func fnPtrInt(_ fn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

final class RuntimeBufferedReaderTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    func testBufferedReaderHandlesMixedLineEndingsAndNoTrailingEmptyLine() throws {
        let fileURL = try makeTempFile(contents: "alpha\r\nbeta\rgamma\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(readerRaw, 0)
        XCTAssertEqual(readString(kk_buffered_reader_readLine(readerRaw)), "alpha")
        XCTAssertEqual(readString(kk_buffered_reader_readLine(readerRaw)), "beta")
        XCTAssertEqual(readString(kk_buffered_reader_readLine(readerRaw)), "gamma")
        XCTAssertEqual(kk_buffered_reader_readLine(readerRaw), runtimeNullSentinelInt)
    }

    func testBufferedReaderEmptyFileIsImmediateEOF() throws {
        let fileURL = try makeTempFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(readerRaw, 0)
        XCTAssertEqual(kk_buffered_reader_readLine(readerRaw), runtimeNullSentinelInt)
        let linesRaw = kk_buffered_reader_readLines(readerRaw)
        XCTAssertEqual(runtimeListBox(from: linesRaw)?.elements.count, 0)
    }

    // MARK: - STDLIB-IO-FN-022: BufferedReader.iterator()

    func testBufferedReaderIteratorYieldsLinesInOrder() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(readerRaw, 0)

        let iterRaw = kk_buffered_reader_iterator(readerRaw)
        XCTAssertNotEqual(iterRaw, 0)
        XCTAssertNotNil(runtimeListIteratorBox(from: iterRaw))

        XCTAssertEqual(kk_iterator_hasNext(iterRaw), 1)
        XCTAssertEqual(readString(kk_iterator_next(iterRaw)), "alpha")
        XCTAssertEqual(kk_iterator_hasNext(iterRaw), 1)
        XCTAssertEqual(readString(kk_iterator_next(iterRaw)), "beta")
        XCTAssertEqual(kk_iterator_hasNext(iterRaw), 1)
        XCTAssertEqual(readString(kk_iterator_next(iterRaw)), "gamma")
        XCTAssertEqual(kk_iterator_hasNext(iterRaw), 0)
    }

    func testBufferedReaderIteratorOnEmptyFileYieldsNoElements() throws {
        let fileURL = try makeTempFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        let iterRaw = kk_buffered_reader_iterator(readerRaw)
        XCTAssertNotEqual(iterRaw, 0)
        XCTAssertEqual(kk_iterator_hasNext(iterRaw), 0)
    }

    // MARK: - STDLIB-IO-FN-033: Reader.readText()

    func testReaderReadTextReturnsRemainingContentsAsSingleString() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(readerRaw, 0)

        let textRaw = kk_reader_readText(readerRaw)
        XCTAssertEqual(readString(textRaw), "alpha\nbeta\ngamma")
    }

    func testReaderReadTextAfterPartialReadReturnsOnlyTheRemainder() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(readString(kk_buffered_reader_readLine(readerRaw)), "alpha")
        let textRaw = kk_reader_readText(readerRaw)
        XCTAssertEqual(readString(textRaw), "beta\ngamma")
    }

    func testReaderReadTextOnEmptyFileReturnsEmptyString() throws {
        let fileURL = try makeTempFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        let textRaw = kk_reader_readText(readerRaw)
        XCTAssertEqual(readString(textRaw), "")
    }

    func testReaderReadTextAfterCloseReturnsEmptyString() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_buffered_reader_close(readerRaw), 0)

        let textRaw = kk_reader_readText(readerRaw)
        XCTAssertEqual(readString(textRaw), "")
    }

    func testReaderReadTextHandlesMultilineUTF8Content() throws {
        let fileURL = try makeTempFile(contents: "α\nβ\nγ")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        let textRaw = kk_reader_readText(readerRaw)
        XCTAssertEqual(readString(textRaw), "α\nβ\nγ")
    }

    func testBufferedReaderIteratorAfterCloseYieldsNoElements() throws {
        let fileURL = try makeTempFile(contents: "first\nsecond\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_buffered_reader_close(readerRaw), 0)

        let iterRaw = kk_buffered_reader_iterator(readerRaw)
        XCTAssertNotEqual(iterRaw, 0)
        XCTAssertEqual(kk_iterator_hasNext(iterRaw), 0)
    }

    func testBufferedReaderCloseStopsReading() throws {
        let fileURL = try makeTempFile(contents: "first\nsecond")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(readString(kk_buffered_reader_readLine(readerRaw)), "first")
        XCTAssertEqual(kk_buffered_reader_close(readerRaw), 0)
        XCTAssertEqual(kk_buffered_reader_readLine(readerRaw), runtimeNullSentinelInt)
        let linesRaw = kk_buffered_reader_readLines(readerRaw)
        XCTAssertEqual(runtimeListBox(from: linesRaw)?.elements.count, 0)
    }

    func testBufferedReaderOpenFailureReturnsNoReaderObject() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        let fileRaw = runtimeTestFileHandle(missingPath)
        let baselineObjectCount = kk_runtime_heap_object_count()

        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(readerRaw, 0)
        XCTAssertEqual(kk_runtime_heap_object_count(), baselineObjectCount)
    }

    func testPathBufferedReaderHandlesSmallBufferReads() throws {
        let fileURL = try makeTempFile(contents: "path-alpha\npath-beta")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_path_bufferedReader(pathRaw, 0, kk_box_int(2), 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(readerRaw, 0)
        XCTAssertEqual(readString(kk_buffered_reader_readLine(readerRaw)), "path-alpha")
        XCTAssertEqual(readString(kk_buffered_reader_readLine(readerRaw)), "path-beta")
        XCTAssertEqual(kk_buffered_reader_readLine(readerRaw), runtimeNullSentinelInt)
    }

    func testPathBufferedReaderOpenFailureReturnsNoReaderObject() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        let pathRaw = runtimeTestPathHandle(missingPath)
        let baselineObjectCount = kk_runtime_heap_object_count()

        var thrown = 0
        let readerRaw = kk_path_bufferedReader(pathRaw, 0, kk_box_int(4096), 0, &thrown)

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(readerRaw, 0)
        XCTAssertEqual(kk_runtime_heap_object_count(), baselineObjectCount)
    }

    // MARK: - STDLIB-IO-FN-040: BufferedReader.useLines

    func testBufferedReaderUseLinesInvokesBlockWithMaterialisedLines() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(readerRaw, 0)

        let result = kk_buffered_reader_useLines(readerRaw, fnPtrInt(useLinesCountsLines), 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_unbox_int(result), 3)
    }

    func testBufferedReaderUseLinesEmptyFileReturnsZeroLines() throws {
        let fileURL = try makeTempFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        let result = kk_buffered_reader_useLines(readerRaw, fnPtrInt(useLinesCountsLines), 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_unbox_int(result), 0)
    }

    func testBufferedReaderUseLinesPropagatesThrownFromBlock() throws {
        let fileURL = try makeTempFile(contents: "one\ntwo\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        let result = kk_buffered_reader_useLines(readerRaw, fnPtrInt(useLinesAlwaysThrows), 0, &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "block exception should surface via outThrown")
    }

    func testBufferedReaderUseLinesClosesReaderAfterBlock() throws {
        let fileURL = try makeTempFile(contents: "first\nsecond\nthird\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        _ = kk_buffered_reader_useLines(readerRaw, fnPtrInt(useLinesCountsLines), 0, &thrown)
        XCTAssertEqual(thrown, 0)

        // After useLines returns, the reader is closed and yields no further lines
        // (mirrors the JVM `use { }` contract on the underlying Reader).
        XCTAssertEqual(kk_buffered_reader_readLine(readerRaw), runtimeNullSentinelInt)
    }

    // MARK: - STDLIB-IO-FN-017: BufferedReader.forEachLine

    func testBufferedReaderForEachLineInvokesActionForEachLine() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        forEachLineCollectedLines = []
        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(readerRaw, 0)

        _ = kk_buffered_reader_forEachLine(readerRaw, fnPtrInt(forEachLineCollector), 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(forEachLineCollectedLines, ["alpha", "beta", "gamma"])
    }

    func testBufferedReaderForEachLineEmptyFileInvokesNoAction() throws {
        let fileURL = try makeTempFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        forEachLineCollectedLines = []
        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        _ = kk_buffered_reader_forEachLine(readerRaw, fnPtrInt(forEachLineCollector), 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(forEachLineCollectedLines, [], "action should not be called for an empty file")
    }

    func testBufferedReaderForEachLinePropagatesThrownFromAction() throws {
        let fileURL = try makeTempFile(contents: "one\ntwo\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        let result = kk_buffered_reader_forEachLine(readerRaw, fnPtrInt(forEachLineAlwaysThrows), 0, &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "action exception should surface via outThrown")
    }

    func testBufferedReaderForEachLineDoesNotCloseReaderAfterIteration() throws {
        let fileURL = try makeTempFile(contents: "first\nsecond\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        forEachLineCollectedLines = []
        _ = kk_buffered_reader_forEachLine(readerRaw, fnPtrInt(forEachLineCollector), 0, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(forEachLineCollectedLines, ["first", "second"])

        // After forEachLine returns, the reader is still open. All lines have been
        // consumed, so the next readLine returns null sentinel — but the reader handle
        // itself is still valid (not released). This differs from useLines.
        XCTAssertEqual(kk_buffered_reader_readLine(readerRaw), runtimeNullSentinelInt,
                       "all lines already consumed; reader still open but at EOF")
    }

    private func makeTempFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func runtimeTestFileHandle(_ path: String) -> Int {
        let bytes = Array(path.utf8)
        let stringRaw = bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
        return kk_file_new(stringRaw)
    }

    private func runtimeTestPathHandle(_ path: String) -> Int {
        let bytes = Array(path.utf8)
        let stringRaw = bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
        return kk_path_new(stringRaw)
    }

    private func readString(_ raw: Int) -> String? {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
    }
}
