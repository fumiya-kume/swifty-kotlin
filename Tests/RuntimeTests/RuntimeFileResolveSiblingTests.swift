import Foundation
@testable import Runtime
import XCTest

/// STDLIB-IO-FN-036: Runtime coverage for `kk_file_resolveSibling_file` and
/// `kk_file_resolveSibling_string`, mirroring kotlin.io.File.resolveSibling
/// semantics (replace the last path component with the sibling name).
final class RuntimeFileResolveSiblingTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    // MARK: - File overload

    func testResolveSiblingFileReplacesLastComponent() {
        let base = makeFileRaw("/tmp/a/b.txt")
        let sibling = makeFileRaw("c.txt")
        let result = extractPath(kk_file_resolveSibling_file(base, sibling))
        XCTAssertEqual(result, "/tmp/a/c.txt")
    }

    func testResolveSiblingFileForBareFilename() {
        // Receiver with no parent directory — sibling is returned as-is
        let base = makeFileRaw("b.txt")
        let sibling = makeFileRaw("c.txt")
        let result = extractPath(kk_file_resolveSibling_file(base, sibling))
        XCTAssertEqual(result, "c.txt")
    }

    func testResolveSiblingFilePreservesDepth() {
        let base = makeFileRaw("/a/b/c/d.txt")
        let sibling = makeFileRaw("e.txt")
        let result = extractPath(kk_file_resolveSibling_file(base, sibling))
        XCTAssertEqual(result, "/a/b/c/e.txt")
    }

    func testResolveSiblingFileForRootLevelFile() {
        // "/foo" has parent "/" so result should be "/bar"
        let base = makeFileRaw("/foo")
        let sibling = makeFileRaw("bar")
        let result = extractPath(kk_file_resolveSibling_file(base, sibling))
        XCTAssertEqual(result, "/bar")
    }

    // MARK: - String overload

    func testResolveSiblingStringReplacesLastComponent() {
        let base = makeFileRaw("/tmp/a/b.txt")
        let result = extractPath(kk_file_resolveSibling_string(base, makeStringRaw("c.txt")))
        XCTAssertEqual(result, "/tmp/a/c.txt")
    }

    func testResolveSiblingStringForBareFilename() {
        let base = makeFileRaw("foo.kt")
        let result = extractPath(kk_file_resolveSibling_string(base, makeStringRaw("bar.kt")))
        XCTAssertEqual(result, "bar.kt")
    }

    func testResolveSiblingStringForRootLevelFile() {
        let base = makeFileRaw("/foo")
        let result = extractPath(kk_file_resolveSibling_string(base, makeStringRaw("bar")))
        XCTAssertEqual(result, "/bar")
    }

    func testResolveSiblingStringProducesFileWithCorrectPath() {
        let base = makeFileRaw("/home/user/documents/report.pdf")
        let raw = kk_file_resolveSibling_string(base, makeStringRaw("summary.pdf"))
        let result = extractPath(raw)
        XCTAssertEqual(result, "/home/user/documents/summary.pdf")
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

    private func extractPath(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: kk_file_path(raw)),
              let path = extractString(from: ptr) else {
            XCTFail("Failed to extract path from File raw value")
            return ""
        }
        return path
    }
}
