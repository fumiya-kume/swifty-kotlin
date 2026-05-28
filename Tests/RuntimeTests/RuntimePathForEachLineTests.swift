import Foundation
@testable import Runtime
import XCTest

// MARK: - STDLIB-IO-PATH-FN-020 lambda thunks for forEachLine
//
// `kk_path_forEachLine` calls kk_function_invoke which dispatches to
// KKFunctionEntryPoint1 = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int.
// The argument is the boxed String raw pointer for the current line.
// These file-scope globals accumulate state across invocations since
// @convention(c) closures cannot capture variables.

nonisolated(unsafe) private var _forEachLineCount: Int = 0

private let forEachLineCounter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    _forEachLineCount += 1
    return 0
}

nonisolated(unsafe) private var _forEachLineLastLength: Int = 0

private let forEachLineRecordLength: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { arg, outThrown in
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: arg),
          let s = extractString(from: ptr)
    else { return 0 }
    _forEachLineLastLength = s.count
    return 0
}

private let forEachLineAlwaysThrows: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "BlockError: forEachLine lambda threw")
    return 0
}

private func fnPtrInt1(_ fn: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

/// Tests for STDLIB-IO-PATH-FN-020: Path.forEachLine
///
/// Covers kk_path_forEachLine and kk_path_forEachLine_default — the runtime
/// entries for the kotlin.io.path.forEachLine extension.
final class RuntimePathForEachLineTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    // MARK: - Helpers

    private func makeRuntimeString(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }

    private func runtimeTestPathHandle(_ path: String) -> Int {
        kk_path_new(makeRuntimeString(path))
    }

    // MARK: - kk_path_forEachLine_default

    func testForEachLineDefaultInvokesOncePerLine() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "alpha\nbeta\ngamma".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        _forEachLineCount = 0
        var thrown = 0
        _ = kk_path_forEachLine_default(pathRaw, fnPtrInt1(forEachLineCounter), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(_forEachLineCount, 3)
    }

    func testForEachLineDefaultEmptyFileProducesNoInvocations() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        _forEachLineCount = 0
        var thrown = 0
        _ = kk_path_forEachLine_default(pathRaw, fnPtrInt1(forEachLineCounter), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(_forEachLineCount, 0)
    }

    func testForEachLineDefaultTrailingNewlineDoesNotProduceEmptyLine() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        // trailing newline should not produce a final empty element
        try "line1\nline2\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        _forEachLineCount = 0
        var thrown = 0
        _ = kk_path_forEachLine_default(pathRaw, fnPtrInt1(forEachLineCounter), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(_forEachLineCount, 2)
    }

    func testForEachLineDefaultNonExistentFileThrows() {
        let pathRaw = runtimeTestPathHandle("/nonexistent/\(UUID().uuidString).txt")
        var thrown = 0
        _ = kk_path_forEachLine_default(pathRaw, fnPtrInt1(forEachLineCounter), &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testForEachLineDefaultLambdaThrownPropagates() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "line1\nline2".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        var thrown = 0
        _ = kk_path_forEachLine_default(pathRaw, fnPtrInt1(forEachLineAlwaysThrows), &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - kk_path_forEachLine (with charset)

    func testForEachLineWithDefaultCharsetInvokesOncePerLine() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "one\ntwo\nthree".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        _forEachLineCount = 0
        var thrown = 0
        // charsetRaw == 0 selects UTF-8 (default)
        _ = kk_path_forEachLine(pathRaw, 0, fnPtrInt1(forEachLineCounter), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(_forEachLineCount, 3)
    }

    func testForEachLinePassesLineContentToAction() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        _forEachLineLastLength = 0
        var thrown = 0
        _ = kk_path_forEachLine(pathRaw, 0, fnPtrInt1(forEachLineRecordLength), &thrown)

        XCTAssertEqual(thrown, 0)
        // "hello" has 5 characters
        XCTAssertEqual(_forEachLineLastLength, 5)
    }
}
