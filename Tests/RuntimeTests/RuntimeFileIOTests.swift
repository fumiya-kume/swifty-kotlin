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

    func testFileExtensionReturnsLastComponentSuffix() {
        XCTAssertEqual(
            readString(kk_file_extension(runtimeTestFileHandle("/tmp/archive.tar.gz"))),
            "gz"
        )
        XCTAssertEqual(
            readString(kk_file_extension(runtimeTestFileHandle("/tmp/README"))),
            ""
        )
        XCTAssertEqual(
            readString(kk_file_extension(runtimeTestFileHandle("/tmp/.gitignore"))),
            "gitignore"
        )
    }

    func testFileInvariantSeparatorsPathRewritesBackslashes() {
        XCTAssertEqual(
            readString(kk_file_invariantSeparatorsPath(runtimeTestFileHandle(#"C:\tmp\archive.tar.gz"#))),
            "C:/tmp/archive.tar.gz"
        )
        XCTAssertEqual(
            readString(kk_file_invariantSeparatorsPath(runtimeTestFileHandle("/tmp/archive.tar.gz"))),
            "/tmp/archive.tar.gz"
        )
    }

    func testFileIsRootedDetectsAbsoluteAndDriveRoots() {
        XCTAssertEqual(kk_unbox_bool(kk_file_isRooted(runtimeTestFileHandle("/tmp/archive.tar.gz"))), 1)
        XCTAssertEqual(kk_unbox_bool(kk_file_isRooted(runtimeTestFileHandle("relative/archive.tar.gz"))), 0)
        XCTAssertEqual(kk_unbox_bool(kk_file_isRooted(runtimeTestFileHandle(#"C:\tmp\archive.tar.gz"#))), 1)
        XCTAssertEqual(kk_unbox_bool(kk_file_isRooted(runtimeTestFileHandle("C:"))), 1)
    }

    func testFileNameWithoutExtensionReturnsLastComponentStem() {
        XCTAssertEqual(
            readString(kk_file_nameWithoutExtension(runtimeTestFileHandle("/tmp/archive.tar.gz"))),
            "archive.tar"
        )
        XCTAssertEqual(
            readString(kk_file_nameWithoutExtension(runtimeTestFileHandle("/tmp/README"))),
            "README"
        )
        XCTAssertEqual(
            readString(kk_file_nameWithoutExtension(runtimeTestFileHandle("/tmp/.gitignore"))),
            ""
        )
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
