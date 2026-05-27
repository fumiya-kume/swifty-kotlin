import Foundation
@testable import Runtime
import XCTest

final class RuntimePathCopyToRecursivelyTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    func testPathCopyToRecursivelyCopiesDirectoryTree() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nestedURL = sourceURL.appendingPathComponent("nested")
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try "root".write(to: sourceURL.appendingPathComponent("root.txt"), atomically: true, encoding: .utf8)
        try "child".write(to: nestedURL.appendingPathComponent("child.txt"), atomically: true, encoding: .utf8)

        var thrown = 0
        let resultRaw = kk_path_copyToRecursively_overwrite(
            runtimeTestPathHandle(sourceURL.path),
            runtimeTestPathHandle(targetURL.path),
            0,
            kk_box_bool(0),
            kk_box_bool(0),
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(resultRaw, 0)
        XCTAssertEqual(
            try String(contentsOf: targetURL.appendingPathComponent("root.txt"), encoding: .utf8),
            "root"
        )
        XCTAssertEqual(
            try String(contentsOf: targetURL.appendingPathComponent("nested/child.txt"), encoding: .utf8),
            "child"
        )
    }

    func testPathCopyToRecursivelyOverwriteReplacesTargetTree() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try "replacement".write(to: sourceURL.appendingPathComponent("value.txt"), atomically: true, encoding: .utf8)
        try "old".write(to: targetURL.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)

        var thrown = 0
        let resultRaw = kk_path_copyToRecursively_overwrite(
            runtimeTestPathHandle(sourceURL.path),
            runtimeTestPathHandle(targetURL.path),
            0,
            kk_box_bool(0),
            kk_box_bool(1),
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(resultRaw, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.appendingPathComponent("old.txt").path))
        XCTAssertEqual(
            try String(contentsOf: targetURL.appendingPathComponent("value.txt"), encoding: .utf8),
            "replacement"
        )
    }

    private func runtimeTestPathHandle(_ path: String) -> Int {
        kk_path_new(makeRuntimeString(path))
    }

    private func makeRuntimeString(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }
}
