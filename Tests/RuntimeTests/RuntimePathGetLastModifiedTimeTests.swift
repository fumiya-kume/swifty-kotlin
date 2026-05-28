import Foundation
@testable import Runtime
import XCTest

final class RuntimePathGetLastModifiedTimeTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

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

    func testGetLastModifiedTimeReturnsPositiveMillisForExistingFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("hello".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        var thrown = 0
        let fileTimeRaw = kk_path_getLastModifiedTime(pathRaw, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        let millis = kk_fileTime_toMillis(fileTimeRaw)
        // The modification time should be a positive number of milliseconds
        // since the Unix epoch (i.e. after 1970-01-01).
        XCTAssertGreaterThan(millis, 0)
    }

    func testGetLastModifiedTimeThrowsForMissingFile() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path

        let pathRaw = runtimeTestPathHandle(missingPath)
        var thrown = 0
        _ = kk_path_getLastModifiedTime(pathRaw, 0, &thrown)

        XCTAssertNotEqual(thrown, 0, "Expected an IOException throwable for a non-existent path")
    }

    func testGetLastModifiedTimeIgnoresOptionsArgument() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("content".utf8).write(to: fileURL)

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        var thrown1 = 0
        var thrown2 = 0
        let fileTimeRaw1 = kk_path_getLastModifiedTime(pathRaw, 0, &thrown1)
        // Pass a non-zero optionsRaw value; it should still succeed and return
        // the same modification time as the default zero-options call.
        let fileTimeRaw2 = kk_path_getLastModifiedTime(pathRaw, 42, &thrown2)

        XCTAssertEqual(thrown1, 0)
        XCTAssertEqual(thrown2, 0)
        XCTAssertEqual(kk_fileTime_toMillis(fileTimeRaw1), kk_fileTime_toMillis(fileTimeRaw2))
    }
}
