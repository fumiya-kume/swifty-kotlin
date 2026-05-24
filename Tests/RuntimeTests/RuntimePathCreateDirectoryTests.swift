import Foundation
@testable import Runtime
import XCTest

final class RuntimePathCreateDirectoryTests: IsolatedRuntimeXCTestCase {
    func testPathCreateDirectoryAttributesCreatesSingleDirectory() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directoryURL = rootURL.appendingPathComponent("leaf")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        var thrown = 0
        let pathRaw = runtimeTestPathHandle(directoryURL.path)
        let resultRaw = kk_path_createDirectory_attributes(pathRaw, 0, &thrown)

        var isDirectory: ObjCBool = false
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(resultRaw, pathRaw)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testPathCreateDirectoryAttributesRequiresExistingParent() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directoryURL = rootURL.appendingPathComponent("missing-parent").appendingPathComponent("leaf")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        var thrown = 0
        let pathRaw = runtimeTestPathHandle(directoryURL.path)
        let resultRaw = kk_path_createDirectory_attributes(pathRaw, 0, &thrown)

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(resultRaw, pathRaw)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.path))
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
