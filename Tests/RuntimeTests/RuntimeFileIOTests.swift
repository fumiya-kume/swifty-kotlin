import Foundation
@testable import Runtime
import XCTest

private var capturedFileBlocks: [[Int]] = []
private var capturedFileBlockSizes: [Int] = []
private let captureFileBlock: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, bufferRaw, bytesRead, _ in
    capturedFileBlocks.append(runtimeListBox(from: bufferRaw)?.elements ?? [])
    capturedFileBlockSizes.append(bytesRead)
    return 0
}

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

    func testAppendBytesCreatesAndAppendsFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0

        XCTAssertEqual(kk_file_appendBytes(fileRaw, registerRuntimeObject(RuntimeListBox(elements: [65, 66])), &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data([65, 66]))

        XCTAssertEqual(kk_file_appendBytes(fileRaw, registerRuntimeObject(RuntimeListBox(elements: [67])), &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data([65, 66, 67]))
    }

    func testFileCopyToCopiesAndHonorsOverwrite() throws {
        let sourceURL = try makeTempFile(contents: "copy me")
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }

        let sourceRaw = runtimeTestFileHandle(sourceURL.path)
        let targetRaw = runtimeTestFileHandle(targetURL.path)
        var thrown = 0

        XCTAssertEqual(kk_file_copyTo_default(sourceRaw, targetRaw, &thrown), targetRaw)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "copy me")

        thrown = 0
        _ = kk_file_copyTo_overwrite(sourceRaw, targetRaw, kk_box_bool(0), &thrown)
        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "copy me")

        try "updated".write(to: sourceURL, atomically: true, encoding: .utf8)
        thrown = 0
        XCTAssertEqual(kk_file_copyTo_overwrite(sourceRaw, targetRaw, kk_box_bool(1), &thrown), targetRaw)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "updated")
    }

    func testFileForEachBlockInvokesActionForChunks() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3, 4, 5]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        capturedFileBlocks.removeAll()
        capturedFileBlockSizes.removeAll()
        let fileRaw = runtimeTestFileHandle(fileURL.path)
        let fnPtr = unsafeBitCast(captureFileBlock, to: Int.self)
        var thrown = 0

        XCTAssertEqual(kk_file_forEachBlock(fileRaw, 2, fnPtr, 0, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(capturedFileBlocks, [[1, 2], [3, 4], [5]])
        XCTAssertEqual(capturedFileBlockSizes, [2, 2, 1])
    }

    func testFileCopyRecursivelyCopiesDirectoryAndHonorsOverwrite() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceURL = rootURL.appendingPathComponent("source")
        let nestedURL = sourceURL.appendingPathComponent("nested")
        let copiedFileURL = nestedURL.appendingPathComponent("value.txt")
        let targetURL = rootURL.appendingPathComponent("target")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try "first".write(to: copiedFileURL, atomically: true, encoding: .utf8)

        let sourceRaw = runtimeTestFileHandle(sourceURL.path)
        let targetRaw = runtimeTestFileHandle(targetURL.path)
        var thrown = 0

        XCTAssertEqual(kk_unbox_bool(kk_file_copyRecursively_default(sourceRaw, targetRaw, &thrown)), 1)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(
            try String(
                contentsOf: targetURL.appendingPathComponent("nested").appendingPathComponent("value.txt"),
                encoding: .utf8
            ),
            "first"
        )

        thrown = 0
        XCTAssertEqual(kk_unbox_bool(kk_file_copyRecursively_overwrite(sourceRaw, targetRaw, kk_box_bool(0), &thrown)), 0)
        XCTAssertNotEqual(thrown, 0)

        try "second".write(to: copiedFileURL, atomically: true, encoding: .utf8)
        thrown = 0
        XCTAssertEqual(kk_unbox_bool(kk_file_copyRecursively_overwrite(sourceRaw, targetRaw, kk_box_bool(1), &thrown)), 1)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(
            try String(
                contentsOf: targetURL.appendingPathComponent("nested").appendingPathComponent("value.txt"),
                encoding: .utf8
            ),
            "second"
        )
    }

    func testStringByteInputStreamReadsEncodedBytes() {
        var thrown = 0
        let streamRaw = kk_string_byteInputStream_default(runtimeStringRaw("ABC"), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), 65)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), 66)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), 67)
        XCTAssertEqual(kk_input_stream_read(streamRaw, &thrown), -1)
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

    func testFileNormalizeResolvesDotsAndDotDots() {
        let normalized = kk_file_normalize(runtimeTestFileHandle("/tmp/alpha/./beta/../gamma.txt"))
        XCTAssertEqual(readString(kk_file_path(normalized)), "/tmp/alpha/gamma.txt")

        let relative = kk_file_normalize(runtimeTestFileHandle("alpha/../beta/./gamma.txt"))
        XCTAssertEqual(readString(kk_file_path(relative)), "beta/gamma.txt")
    }

    func testFileResolveSiblingUsesParentDirectory() {
        let source = runtimeTestFileHandle("/tmp/alpha/source.txt")

        let stringSibling = kk_file_resolveSibling_string(source, runtimeStringRaw("other.txt"))
        XCTAssertEqual(readString(kk_file_path(stringSibling)), "/tmp/alpha/other.txt")

        let fileSibling = kk_file_resolveSibling_file(source, runtimeTestFileHandle("nested/other.txt"))
        XCTAssertEqual(readString(kk_file_path(fileSibling)), "/tmp/alpha/nested/other.txt")

        let noParentSibling = kk_file_resolveSibling_string(runtimeTestFileHandle("source.txt"), runtimeStringRaw("other.txt"))
        XCTAssertEqual(readString(kk_file_path(noParentSibling)), "other.txt")
    }

    func testFileStartsWithComparesRootsAndComponents() {
        let file = runtimeTestFileHandle("/tmp/alpha/beta.txt")
        XCTAssertEqual(kk_unbox_bool(kk_file_startsWith_string(file, runtimeStringRaw("/tmp/alpha"))), 1)
        XCTAssertEqual(kk_unbox_bool(kk_file_startsWith_string(file, runtimeStringRaw("/tmp/alph"))), 0)
        XCTAssertEqual(kk_unbox_bool(kk_file_startsWith_file(file, runtimeTestFileHandle("/tmp"))), 1)
        XCTAssertEqual(kk_unbox_bool(kk_file_startsWith_file(file, runtimeTestFileHandle("tmp"))), 0)
    }

    func testFileToRelativeStringUsesBaseDirectory() {
        XCTAssertEqual(
            readString(kk_file_toRelativeString(
                runtimeTestFileHandle("/tmp/alpha/beta/gamma.txt"),
                runtimeTestFileHandle("/tmp/alpha")
            )),
            "beta/gamma.txt"
        )
        XCTAssertEqual(
            readString(kk_file_toRelativeString(
                runtimeTestFileHandle("/tmp/alpha/gamma.txt"),
                runtimeTestFileHandle("/tmp/alpha/beta")
            )),
            "../gamma.txt"
        )
        XCTAssertEqual(
            readString(kk_file_toRelativeString(
                runtimeTestFileHandle("/tmp/alpha"),
                runtimeTestFileHandle("/tmp/alpha")
            )),
            "."
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
