import Foundation
@testable import Runtime
import XCTest

// MARK: - STDLIB-IO-FN-016: File.forEachBlock lambda thunks
// Lambda ABI: (closureRaw: Int, bytesRaw: Int, bytesReadRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int
private nonisolated(unsafe) var forEachBlockAccumulator: Int = 0
private nonisolated(unsafe) var forEachBlockChunkCount: Int = 0

// Counts total bytesRead across all callback invocations
private let forEachBlockCountBytes: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, bytesReadRaw, outThrown in
    outThrown?.pointee = 0
    forEachBlockAccumulator += kk_unbox_int(bytesReadRaw)
    return 0
}

// Counts chunks and accumulates bytesRead
private let forEachBlockCountChunks: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, bytesReadRaw, outThrown in
    outThrown?.pointee = 0
    forEachBlockChunkCount += 1
    forEachBlockAccumulator += kk_unbox_int(bytesReadRaw)
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

    // STDLIB-IO-FN-016: File.forEachBlock — default blockSize accumulates all bytes
    func testForEachBlockDefaultBlockSizeAccumulatesAllBytes() throws {
        let bytes: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(bytes).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)

        forEachBlockAccumulator = 0
        let fnPtr = Int(bitPattern: unsafeBitCast(
            forEachBlockCountBytes as @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int,
            to: UnsafeRawPointer.self
        ))
        var thrown = 0
        _ = kk_file_forEachBlock(fileRaw, fnPtr, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(forEachBlockAccumulator, 8)
    }

    // STDLIB-IO-FN-016: File.forEachBlock — explicit blockSize splits data into chunks
    func testForEachBlockWithExplicitBlockSizeProcessesChunks() throws {
        let bytes: [UInt8] = [10, 20, 30, 40, 50, 60]
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(bytes).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)

        forEachBlockChunkCount = 0
        forEachBlockAccumulator = 0
        let fnPtr = Int(bitPattern: unsafeBitCast(
            forEachBlockCountChunks as @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int,
            to: UnsafeRawPointer.self
        ))
        // blockSize = 2 → should produce 3 chunks of 2 bytes each
        let blockSizeRaw = kk_box_int(2)
        var thrown = 0
        _ = kk_file_forEachBlock_blockSize(fileRaw, blockSizeRaw, fnPtr, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(forEachBlockChunkCount, 3)
        XCTAssertEqual(forEachBlockAccumulator, 6) // 3 chunks × 2 bytes each
    }

    // MARK: - STDLIB-IO-PROP-002: File.extension property

    func testExtensionReturnsSubstringAfterLastDot() {
        let fileRaw = runtimeTestFileHandle("/tmp/Main.kt")
        XCTAssertEqual(readString(kk_file_extension(fileRaw)), "kt")
    }

    func testExtensionWithMultipleDotsReturnsLastSegment() {
        let fileRaw = runtimeTestFileHandle("/tmp/archive.tar.gz")
        XCTAssertEqual(readString(kk_file_extension(fileRaw)), "gz")
    }

    func testExtensionReturnsEmptyStringWhenNoDot() {
        let fileRaw = runtimeTestFileHandle("/tmp/README")
        XCTAssertEqual(readString(kk_file_extension(fileRaw)), "")
    }

    func testExtensionIgnoresParentDirectoryDots() {
        // The dot in the parent directory must not be treated as the extension
        // separator — only the last path component matters.
        let fileRaw = runtimeTestFileHandle("/var/data.v2/payload")
        XCTAssertEqual(readString(kk_file_extension(fileRaw)), "")
    }

    func testExtensionForDotFileMatchesKotlinJvmBehavior() {
        // Kotlin/JVM treats `.bashrc` as a name whose extension is "bashrc"
        // because `File("/tmp/.bashrc").name == ".bashrc"` and the only dot is
        // at index 0; the substring after it is `"bashrc"`.
        let fileRaw = runtimeTestFileHandle("/tmp/.bashrc")
        XCTAssertEqual(readString(kk_file_extension(fileRaw)), "bashrc")
    }

    func testExtensionForRelativePathName() {
        let fileRaw = runtimeTestFileHandle("Main.kt")
        XCTAssertEqual(readString(kk_file_extension(fileRaw)), "kt")
    }

    func testExtensionWithTrailingDotReturnsEmptyTail() {
        // `File("/tmp/file.").extension` → "" — the dot is the last character so
        // the substring after it is the empty string.
        let fileRaw = runtimeTestFileHandle("/tmp/file.")
        XCTAssertEqual(readString(kk_file_extension(fileRaw)), "")
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

    // MARK: - STDLIB-IO-FN-038: File.toRelativeString(base: File): String

    func testToRelativeStringReturnsDescendantPath() {
        let fileRaw = runtimeTestFileHandle("/a/b/c")
        let baseRaw = runtimeTestFileHandle("/a/b")
        var thrown = 0
        let resultRaw = kk_file_toRelativeString(fileRaw, baseRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(readString(resultRaw), "c")
    }

    func testToRelativeStringReturnsAscendantPath() {
        let fileRaw = runtimeTestFileHandle("/a/b")
        let baseRaw = runtimeTestFileHandle("/a/b/c/d")
        var thrown = 0
        let resultRaw = kk_file_toRelativeString(fileRaw, baseRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(readString(resultRaw), "../..")
    }

    func testToRelativeStringReturnsSiblingPath() {
        let fileRaw = runtimeTestFileHandle("/a/x")
        let baseRaw = runtimeTestFileHandle("/a/b/c")
        var thrown = 0
        let resultRaw = kk_file_toRelativeString(fileRaw, baseRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(readString(resultRaw), "../../x")
    }

    func testToRelativeStringReturnsEmptyForEqualPaths() {
        let fileRaw = runtimeTestFileHandle("/a/b")
        let baseRaw = runtimeTestFileHandle("/a/b")
        var thrown = 0
        let resultRaw = kk_file_toRelativeString(fileRaw, baseRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(readString(resultRaw), "")
    }

    func testToRelativeStringNormalisesTrailingAndDoubleSeparators() {
        let fileRaw = runtimeTestFileHandle("/a//b/c/")
        let baseRaw = runtimeTestFileHandle("/a/b/")
        var thrown = 0
        let resultRaw = kk_file_toRelativeString(fileRaw, baseRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(readString(resultRaw), "c")
    }

    func testToRelativeStringWorksForRelativePaths() {
        let fileRaw = runtimeTestFileHandle("a/b/c")
        let baseRaw = runtimeTestFileHandle("a/b")
        var thrown = 0
        let resultRaw = kk_file_toRelativeString(fileRaw, baseRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(readString(resultRaw), "c")
    }

    func testToRelativeStringThrowsForMismatchedRoots() {
        let fileRaw = runtimeTestFileHandle("/a/b")
        let baseRaw = runtimeTestFileHandle("a/b")
        var thrown = 0
        _ = kk_file_toRelativeString(fileRaw, baseRaw, &thrown)

        XCTAssertNotEqual(thrown, 0, "Different roots should surface a thrown exception")
        guard let ptr = UnsafeMutableRawPointer(bitPattern: thrown),
              let box = tryCast(ptr, to: RuntimeThrowableBox.self) else {
            XCTFail("Expected a throwable allocated for mismatched roots"); return
        }
        XCTAssertTrue(
            box is RuntimeIllegalArgumentExceptionBox,
            "Mismatched roots must surface IllegalArgumentException, got \(box.exceptionFQName)"
        )
    }

    /// STDLIB-IO-PROP-004: `File.isRooted` returns `true` when the path begins
    /// with a Unix root, a Windows drive letter, or a UNC/backslash prefix,
    /// and `false` for empty or relative paths. Covers the helper directly so
    /// the deterministic logic stays in lock-step with Kotlin's
    /// `FilePathComponents.root.isNotEmpty()` semantics.
    func testRuntimeFilePathIsRootedHelper() {
        // Unix-style roots
        XCTAssertTrue(runtimeFilePathIsRooted("/"))
        XCTAssertTrue(runtimeFilePathIsRooted("/etc/hosts"))
        // Windows-style roots (drive letter or drive+separator)
        XCTAssertTrue(runtimeFilePathIsRooted("C:\\Windows"))
        XCTAssertTrue(runtimeFilePathIsRooted("c:/Users"))
        XCTAssertTrue(runtimeFilePathIsRooted("Z:"))
        // Backslash / UNC prefix
        XCTAssertTrue(runtimeFilePathIsRooted("\\foo"))
        XCTAssertTrue(runtimeFilePathIsRooted("\\\\server\\share"))
        // Relative or empty paths
        XCTAssertFalse(runtimeFilePathIsRooted(""))
        XCTAssertFalse(runtimeFilePathIsRooted("relative.txt"))
        XCTAssertFalse(runtimeFilePathIsRooted("./local"))
        XCTAssertFalse(runtimeFilePathIsRooted("foo/bar"))
        // Non-letter drive prefix is not a root.
        XCTAssertFalse(runtimeFilePathIsRooted("1:foo"))
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
