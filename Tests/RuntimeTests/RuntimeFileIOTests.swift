import Foundation
@testable import Runtime
import XCTest

final class RuntimeFileIOTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    func testReadTextReturnsUtf8Contents() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let textRaw = kk_file_readText(fileRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(readString(textRaw), "alpha\nbeta")
    }

    func testAppendTextCreatesAndAppendsFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0

        XCTAssertEqual(kk_file_appendText(fileRaw, runtimeStringRaw("alpha"), &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha")

        XCTAssertEqual(kk_file_appendText(fileRaw, runtimeStringRaw("\nbeta"), &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha\nbeta")
    }

    func testReadBytesReturnsSignedByteValues() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0, 127, 128, 255]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let bytesRaw = kk_file_readBytes(fileRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeListBox(from: bytesRaw)?.elements, [0, 127, -128, -1])
    }

    // STDLIB-IO-FN-001: File.appendBytes(array: ByteArray)
    func testAppendBytesCreatesAndAppendsFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0

        // Write initial bytes [1, 2, 3]
        let bytesRaw1 = registerRuntimeObject(RuntimeListBox(elements: [1, 2, 3]))
        XCTAssertEqual(kk_file_appendBytes(fileRaw, bytesRaw1, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data([1, 2, 3]))

        // Append additional bytes [4, 5]
        let bytesRaw2 = registerRuntimeObject(RuntimeListBox(elements: [4, 5]))
        XCTAssertEqual(kk_file_appendBytes(fileRaw, bytesRaw2, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data([1, 2, 3, 4, 5]))
    }

    func testAppendBytesHandlesSignedByteValues() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0

        // Kotlin Byte range: -128 to 127; -1 maps to 0xFF, -128 to 0x80
        let bytesRaw = registerRuntimeObject(RuntimeListBox(elements: [0, 127, -128, -1]))
        XCTAssertEqual(kk_file_appendBytes(fileRaw, bytesRaw, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data([0, 127, 128, 255]))
    }

    // STDLIB-IO-PROP-005: File.nameWithoutExtension extension property
    func testNameWithoutExtensionStripsTrailingExtension() {
        let cases: [(path: String, expected: String)] = [
            ("/tmp/archive.tar.gz", "archive.tar"),
            ("/tmp/README", "README"),
            ("/tmp/.gitignore", ""),
            ("/tmp/notes.txt", "notes"),
            ("relative/file.kt", "file"),
            ("/tmp/", "tmp"),
            ("plain.name", "plain"),
        ]
        for (path, expected) in cases {
            let fileRaw = runtimeTestFileHandle(path)
            let nameRaw = kk_file_nameWithoutExtension(fileRaw)
            XCTAssertEqual(
                readString(nameRaw),
                expected,
                "nameWithoutExtension for \(path) should be \(expected)"
            )
        }
    }

    private func makeTempFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func runtimeTestFileHandle(_ path: String) -> Int {
        kk_file_new(runtimeStringRaw(path))
    }

    private func runtimeStringRaw(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }

    private func readString(_ raw: Int) -> String? {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
    }
}
