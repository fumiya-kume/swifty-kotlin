import Foundation
@testable import Runtime
import XCTest

/// STDLIB-IO-FN-024: Runtime tests for `kk_file_normalize`.
///
/// Mirrors the behaviour of `kotlin.io.File.normalize()`:
///   public fun File.normalize(): File
///
/// The function resolves "." and ".." path components lexically (no filesystem
/// access), preserves the absolute/relative nature of the path, and returns a
/// new File wrapping the resulting path string.
final class RuntimeFileNormalizeTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    // MARK: - Absolute paths

    func testNormalizeSingleDotInAbsolutePath() {
        let file = makeFileRaw("/tmp/./sub/file.txt")
        XCTAssertEqual(extractFilePath(kk_file_normalize(file)), "/tmp/sub/file.txt")
    }

    func testNormalizeDoubleDotInAbsolutePath() {
        let file = makeFileRaw("/tmp/sub/../file.txt")
        XCTAssertEqual(extractFilePath(kk_file_normalize(file)), "/tmp/file.txt")
    }

    func testNormalizeMultipleDoubleDots() {
        let file = makeFileRaw("/a/b/c/../../d")
        XCTAssertEqual(extractFilePath(kk_file_normalize(file)), "/a/d")
    }

    func testNormalizeAlreadyNormalAbsolutePath() {
        let file = makeFileRaw("/usr/local/bin")
        XCTAssertEqual(extractFilePath(kk_file_normalize(file)), "/usr/local/bin")
    }

    func testNormalizeRootPath() {
        let file = makeFileRaw("/")
        XCTAssertEqual(extractFilePath(kk_file_normalize(file)), "/")
    }

    func testNormalizeDoubleDotAtRootStaysAtRoot() {
        // Going up from root should clamp to root
        let file = makeFileRaw("/tmp/../..")
        XCTAssertEqual(extractFilePath(kk_file_normalize(file)), "/")
    }

    // MARK: - Relative paths

    func testNormalizeSingleDotInRelativePath() {
        let file = makeFileRaw("a/./b/c")
        XCTAssertEqual(extractFilePath(kk_file_normalize(file)), "a/b/c")
    }

    func testNormalizeDoubleDotInRelativePath() {
        let file = makeFileRaw("a/b/../c")
        XCTAssertEqual(extractFilePath(kk_file_normalize(file)), "a/c")
    }

    func testNormalizeRelativePathLeadingDoubleDotPreserved() {
        // "../x" cannot be resolved further — the leading ".." is kept
        let file = makeFileRaw("../x/y")
        XCTAssertEqual(extractFilePath(kk_file_normalize(file)), "../x/y")
    }

    func testNormalizeCurrentDirRelativePath() {
        let file = makeFileRaw(".")
        XCTAssertEqual(extractFilePath(kk_file_normalize(file)), ".")
    }

    func testNormalizePathCollapsingToEmptyReturnsDot() {
        // A relative path that fully resolves to nothing returns "."
        let file = makeFileRaw("a/..")
        XCTAssertEqual(extractFilePath(kk_file_normalize(file)), ".")
    }

    // MARK: - Return value is a new File handle

    func testNormalizeReturnsNewFileHandleWithCorrectPath() {
        let original = makeFileRaw("/tmp/./sub/../file.txt")
        let normalized = kk_file_normalize(original)
        XCTAssertNotEqual(original, normalized, "normalize must return a new File box")
        XCTAssertEqual(extractFilePath(normalized), "/tmp/file.txt")
    }

    // MARK: - Helpers

    private func makeFileRaw(_ path: String) -> Int {
        kk_file_new(makeStringRaw(path))
    }

    private func makeStringRaw(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }

    private func extractFilePath(_ fileRaw: Int) -> String? {
        let pathRaw = kk_file_path(fileRaw)
        return extractString(from: UnsafeMutableRawPointer(bitPattern: pathRaw))
    }
}
