import Foundation
@testable import Runtime
import XCTest

final class RuntimeBufferedWriterTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    func testPathBufferedWriterWritesAndTruncatesFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "old-content".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let writerRaw = kk_path_bufferedWriter(
            runtimeTestPathHandle(fileURL.path),
            0,
            kk_box_int(2),
            0
        )
        XCTAssertNotEqual(writerRaw, 0)

        var thrown = 0
        XCTAssertEqual(kk_buffered_writer_write(writerRaw, makeStringRaw("alpha"), &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_buffered_writer_new_line(writerRaw, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_buffered_writer_write(writerRaw, makeStringRaw("beta"), &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_buffered_writer_flush(writerRaw, &thrown), 0)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha\nbeta")
        XCTAssertEqual(kk_buffered_writer_close(writerRaw), 0)
    }

    // STDLIB-IO-FN-009: OutputStream.bufferedWriter(charset)
    func testOutputStreamBufferedWriterWritesUtf8Bytes() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "old-content".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let fileRaw = kk_file_new(makeStringRaw(fileURL.path))
        XCTAssertNotEqual(fileRaw, 0)

        let streamRaw = kk_file_outputStream(fileRaw, &thrown)
        XCTAssertNotEqual(streamRaw, 0)
        XCTAssertEqual(thrown, 0)

        // charsetRaw = 0 corresponds to UTF-8 (mirrors Charsets.UTF_8).
        let writerRaw = kk_output_stream_bufferedWriter(streamRaw, 0)
        XCTAssertNotEqual(writerRaw, 0)

        XCTAssertEqual(kk_buffered_writer_write(writerRaw, makeStringRaw("hello"), &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_buffered_writer_new_line(writerRaw, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_buffered_writer_write(writerRaw, makeStringRaw("world"), &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_buffered_writer_flush(writerRaw, &thrown), 0)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "hello\nworld")
        XCTAssertEqual(kk_buffered_writer_close(writerRaw), 0)
    }

    func testOutputStreamBufferedWriterDefaultUsesUtf8() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let fileRaw = kk_file_new(makeStringRaw(fileURL.path))
        XCTAssertNotEqual(fileRaw, 0)
        let streamRaw = kk_file_outputStream(fileRaw, &thrown)
        XCTAssertNotEqual(streamRaw, 0)

        let writerRaw = kk_output_stream_bufferedWriter_default(streamRaw)
        XCTAssertNotEqual(writerRaw, 0)

        XCTAssertEqual(kk_buffered_writer_write(writerRaw, makeStringRaw("默认 utf-8"), &thrown), 0)
        XCTAssertEqual(kk_buffered_writer_flush(writerRaw, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "默认 utf-8")
        XCTAssertEqual(kk_buffered_writer_close(writerRaw), 0)
    }

    private func makeStringRaw(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }

    private func runtimeTestPathHandle(_ path: String) -> Int {
        kk_path_new(makeStringRaw(path))
    }
}
