import Foundation
@testable import Runtime
import XCTest

final class RuntimeStreamTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    func testInputStreamReadAvailableSkipAndClose() throws {
        let fileURL = try makeTempFile(contents: "abcd")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let streamRaw = kk_file_inputStream(fileRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_input_stream_available(streamRaw), 4)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), 97)
        XCTAssertEqual(kk_input_stream_skip(streamRaw, 1, &thrown), 1)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), 99)
        XCTAssertEqual(kk_input_stream_close(streamRaw), 0)
        XCTAssertEqual(kk_input_stream_available(streamRaw), 0)
    }

    func testInputStreamReadIntoByteArrayLikeBuffer() throws {
        let fileURL = try makeTempFile(contents: "xyz")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let streamRaw = kk_file_inputStream(fileRaw, &thrown)
        let bufferRaw = registerRuntimeObject(RuntimeListBox(elements: [0, 0, 0, 0]))

        XCTAssertEqual(kk_input_stream_read_bytes(streamRaw, bufferRaw, &thrown), 3)
        XCTAssertEqual(runtimeListBox(from: bufferRaw)?.elements.prefix(3).map(UInt8.init(truncatingIfNeeded:)), [120, 121, 122])
    }

    func testByteArrayInputStreamExtensionReadsBytes() {
        let bytesRaw = registerRuntimeObject(RuntimeListBox(elements: [65, 66, 67]))
        var thrown = 0
        let streamRaw = kk_bytearray_inputStream(bytesRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), 65)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), 66)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), 67)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), -1)
    }

    func testByteArrayInputStreamRangeExtensionReadsSlice() {
        let bytesRaw = registerRuntimeObject(RuntimeListBox(elements: [65, 66, 67, 68]))
        var thrown = 0
        let streamRaw = kk_bytearray_inputStream_range(bytesRaw, 1, 2, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), 66)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), 67)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), -1)
    }

    func testOutputStreamWriteByteAndBytesPersistToFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let streamRaw = kk_file_outputStream(fileRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        _ = kk_output_stream_write_byte(streamRaw, 65, &thrown)
        let bytesRaw = registerRuntimeObject(RuntimeListBox(elements: [66, 67]))
        _ = kk_output_stream_write_bytes(streamRaw, bytesRaw, &thrown)
        _ = kk_output_stream_flush(streamRaw, &thrown)
        _ = kk_output_stream_close(streamRaw)

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(contents, "ABC")
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
}
