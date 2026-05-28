import Foundation
@testable import Runtime
import XCTest

/// STDLIB-IO-FN-037: Runtime coverage for `kk_file_startsWith_file` and
/// `kk_file_startsWith_string`, mirroring kotlin.io.File.startsWith semantics
/// (component-by-component prefix match, sensitive to absoluteness).
final class RuntimeFileStartsWithTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    func testStartsWithFileMatchesParentDirectory() {
        let child = makeFileRaw("/tmp/sub/file.txt")
        let parent = makeFileRaw("/tmp")
        XCTAssertEqual(unboxBool(kk_file_startsWith_file(child, parent)), true)
    }

    func testStartsWithFileMatchesSamePath() {
        let path = makeFileRaw("/var/log/system.log")
        XCTAssertEqual(unboxBool(kk_file_startsWith_file(path, makeFileRaw("/var/log/system.log"))), true)
    }

    func testStartsWithFileReturnsFalseForUnrelatedPath() {
        let child = makeFileRaw("/usr/local/bin/tool")
        let other = makeFileRaw("/tmp")
        XCTAssertEqual(unboxBool(kk_file_startsWith_file(child, other)), false)
    }

    func testStartsWithFileRequiresMatchingAbsoluteness() {
        let absolute = makeFileRaw("/tmp/sub/file.txt")
        let relative = makeFileRaw("tmp/sub")
        XCTAssertEqual(unboxBool(kk_file_startsWith_file(absolute, relative)), false)
        XCTAssertEqual(unboxBool(kk_file_startsWith_file(relative, absolute)), false)
    }

    func testStartsWithFileRejectsPartialComponentPrefix() {
        // "/tmp/subdir" must not be considered a prefix of "/tmp/sub" — the
        // comparison happens component-by-component, not on the raw substring.
        let child = makeFileRaw("/tmp/sub")
        let other = makeFileRaw("/tmp/subdir")
        XCTAssertEqual(unboxBool(kk_file_startsWith_file(child, other)), false)
    }

    func testStartsWithFileWorksOnRelativeReceiver() {
        let child = makeFileRaw("a/b/c")
        XCTAssertEqual(unboxBool(kk_file_startsWith_file(child, makeFileRaw("a/b"))), true)
        XCTAssertEqual(unboxBool(kk_file_startsWith_file(child, makeFileRaw("a/b/c/d"))), false)
    }

    func testStartsWithStringDelegatesToComponentComparison() {
        let child = makeFileRaw("/tmp/sub/file.txt")
        XCTAssertEqual(unboxBool(kk_file_startsWith_string(child, makeStringRaw("/tmp"))), true)
        XCTAssertEqual(unboxBool(kk_file_startsWith_string(child, makeStringRaw("/tmp/sub"))), true)
        XCTAssertEqual(unboxBool(kk_file_startsWith_string(child, makeStringRaw("/var"))), false)
        XCTAssertEqual(unboxBool(kk_file_startsWith_string(child, makeStringRaw("tmp"))), false)
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

    private func unboxBool(_ raw: Int) -> Bool {
        kk_unbox_bool(raw) != 0
    }
}
