import Foundation
@testable import Runtime
import XCTest

/// STDLIB-IO-FN-012: Runtime tests for `kk_file_copyRecursively`.
///
/// Mirrors the behaviour of `kotlin.io.copyRecursively` on `java.io.File`:
///   public fun File.copyRecursively(
///       target: File,
///       overwrite: Boolean = false,
///       onError: (File, IOException) -> OnErrorAction = { _, exception -> throw exception }
///   ): Boolean
final class RuntimeFileCopyRecursivelyTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    // MARK: - Happy paths

    func testCopyRecursivelyFlatFileCopiesContents() throws {
        let sourceURL = try makeTempFile(contents: "hello world")
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }

        let sourceRaw = runtimeTestFileHandle(sourceURL.path)
        let targetRaw = runtimeTestFileHandle(targetURL.path)
        var thrown = 0
        let resultRaw = kk_file_copyRecursively(sourceRaw, targetRaw, kk_box_bool(0), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(kk_unbox_bool(resultRaw), 0) // true
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "hello world")
    }

    func testCopyRecursivelyDirectoryWithFilesCopiesToTarget() throws {
        let sourceDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileA = sourceDir.appendingPathComponent("a.txt")
        let fileB = sourceDir.appendingPathComponent("b.txt")
        try "alpha".write(to: fileA, atomically: true, encoding: .utf8)
        try "beta".write(to: fileB, atomically: true, encoding: .utf8)

        let targetDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        let sourceRaw = runtimeTestFileHandle(sourceDir.path)
        let targetRaw = runtimeTestFileHandle(targetDir.path)
        var thrown = 0
        let resultRaw = kk_file_copyRecursively(sourceRaw, targetRaw, kk_box_bool(0), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(kk_unbox_bool(resultRaw), 0) // true
        XCTAssertEqual(
            try String(contentsOf: targetDir.appendingPathComponent("a.txt"), encoding: .utf8),
            "alpha"
        )
        XCTAssertEqual(
            try String(contentsOf: targetDir.appendingPathComponent("b.txt"), encoding: .utf8),
            "beta"
        )
    }

    func testCopyRecursivelyNestedDirectoryStructure() throws {
        let sourceDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let subDir = sourceDir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let deepFile = subDir.appendingPathComponent("deep.txt")
        try "deep content".write(to: deepFile, atomically: true, encoding: .utf8)

        let targetDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        let sourceRaw = runtimeTestFileHandle(sourceDir.path)
        let targetRaw = runtimeTestFileHandle(targetDir.path)
        var thrown = 0
        let resultRaw = kk_file_copyRecursively(sourceRaw, targetRaw, kk_box_bool(0), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(kk_unbox_bool(resultRaw), 0) // true
        let copiedDeep = targetDir.appendingPathComponent("sub").appendingPathComponent("deep.txt")
        XCTAssertEqual(try String(contentsOf: copiedDeep, encoding: .utf8), "deep content")
    }

    func testCopyRecursivelyWithOverwriteReplacesExistingFile() throws {
        let sourceDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let srcFile = sourceDir.appendingPathComponent("file.txt")
        let dstFile = targetDir.appendingPathComponent("file.txt")
        try "new content".write(to: srcFile, atomically: true, encoding: .utf8)
        try "old content".write(to: dstFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        let sourceRaw = runtimeTestFileHandle(sourceDir.path)
        let targetRaw = runtimeTestFileHandle(targetDir.path)
        var thrown = 0
        let resultRaw = kk_file_copyRecursively(sourceRaw, targetRaw, kk_box_bool(1), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(kk_unbox_bool(resultRaw), 0) // true
        XCTAssertEqual(try String(contentsOf: dstFile, encoding: .utf8), "new content")
    }

    // MARK: - Edge cases

    func testCopyRecursivelyOnNonExistentSourceReturnsFalse() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let sourceRaw = runtimeTestFileHandle(sourceURL.path)
        let targetRaw = runtimeTestFileHandle(targetURL.path)
        var thrown = 0
        let resultRaw = kk_file_copyRecursively(sourceRaw, targetRaw, kk_box_bool(0), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_unbox_bool(resultRaw), 0) // false — source does not exist
    }

    func testCopyRecursivelyWithoutOverwriteThrowsOnExistingFile() throws {
        let sourceDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let targetDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let srcFile = sourceDir.appendingPathComponent("conflict.txt")
        let dstFile = targetDir.appendingPathComponent("conflict.txt")
        try "source".write(to: srcFile, atomically: true, encoding: .utf8)
        try "target".write(to: dstFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        let sourceRaw = runtimeTestFileHandle(sourceDir.path)
        let targetRaw = runtimeTestFileHandle(targetDir.path)
        var thrown = 0
        _ = kk_file_copyRecursively(sourceRaw, targetRaw, kk_box_bool(0), &thrown)

        // Without overwrite, a conflicting file should produce a thrown exception.
        XCTAssertNotEqual(thrown, 0)
        // The existing target file must be untouched.
        XCTAssertEqual(try String(contentsOf: dstFile, encoding: .utf8), "target")
    }

    // MARK: - Helpers

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
}
