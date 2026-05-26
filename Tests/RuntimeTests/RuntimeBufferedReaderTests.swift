import Foundation
@testable import Runtime
import XCTest

private var capturedReaderForEachLines: [String] = []
private let captureReaderForEachLine: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lineRaw, _ in
    capturedReaderForEachLines.append(extractString(from: UnsafeMutableRawPointer(bitPattern: lineRaw)) ?? "")
    return 0
}
private var capturedReaderUseLines: [String] = []
private let captureReaderUseLines: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, linesRaw, _ in
    let lines = runtimeListBox(from: linesRaw)?.elements ?? []
    capturedReaderUseLines = lines.map { extractString(from: UnsafeMutableRawPointer(bitPattern: $0)) ?? "" }
    return lines.count
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

    func testReaderBufferedReturnsReadableReader() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)
        let bufferedRaw = kk_reader_buffered_default(readerRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(readString(kk_buffered_reader_readLine(bufferedRaw)), "alpha")
        XCTAssertEqual(readString(kk_buffered_reader_readLine(bufferedRaw)), "beta")
        XCTAssertEqual(kk_buffered_reader_readLine(bufferedRaw), runtimeNullSentinelInt)
    }

    func testReaderReadTextReadsRemainingContents() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)

        XCTAssertEqual(readString(kk_buffered_reader_readLine(readerRaw)), "alpha")
        let textRaw = kk_reader_readText(readerRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(readString(textRaw), "beta\ngamma")
    }

    func testReaderForEachLineInvokesActionForRemainingLines() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)

        XCTAssertEqual(readString(kk_buffered_reader_readLine(readerRaw)), "alpha")
        capturedReaderForEachLines.removeAll()
        let fnPtr = unsafeBitCast(captureReaderForEachLine, to: Int.self)
        let result = kk_reader_forEachLine(readerRaw, fnPtr, 0, &thrown)

        XCTAssertEqual(result, 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(capturedReaderForEachLines, ["beta", "gamma"])
    }

    func testReaderUseLinesInvokesBlockAndClosesReader() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(fileRaw, &thrown)

        XCTAssertEqual(readString(kk_buffered_reader_readLine(readerRaw)), "alpha")
        capturedReaderUseLines.removeAll()
        let fnPtr = unsafeBitCast(captureReaderUseLines, to: Int.self)
        let result = kk_reader_useLines(readerRaw, fnPtr, 0, &thrown)

        XCTAssertEqual(result, 2)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(capturedReaderUseLines, ["beta", "gamma"])
        XCTAssertEqual(kk_buffered_reader_readLine(readerRaw), runtimeNullSentinelInt)
    }

    func testReaderCopyToWritesRemainingContentsToWriter() throws {
        let sourceURL = try makeTempFile(contents: "alpha\nbeta\ngamma")
        let targetURL = try makeTempFile(contents: "old")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }

        let sourceRaw = runtimeTestFileHandle(sourceURL.path)
        let targetRaw = runtimeTestFileHandle(targetURL.path)
        var thrown = 0
        let readerRaw = kk_file_bufferedReader(sourceRaw, &thrown)
        let writerRaw = kk_file_bufferedWriter(targetRaw, &thrown)

        XCTAssertEqual(readString(kk_buffered_reader_readLine(readerRaw)), "alpha")
        let result = kk_reader_copyTo_default(readerRaw, writerRaw, &thrown)
        XCTAssertEqual(kk_buffered_writer_flush(writerRaw, &thrown), 0)

        XCTAssertEqual(result, "beta\ngamma".utf8.count)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "beta\ngamma")
        XCTAssertEqual(kk_buffered_writer_close(writerRaw), 0)
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
