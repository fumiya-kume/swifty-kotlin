import Foundation
@testable import Runtime
import XCTest

final class RuntimePathCreateTempDirectoryTests: IsolatedRuntimeXCTestCase {
    func testPathCreateTempDirectoryPrefixAttributesCreatesDirectory() throws {
        var thrown = 0
        let resultRaw = kk_path_createTempDirectory_prefix_attributes(makeRuntimeString("kswiftk-"), 0, &thrown)
        let createdPath = extractStringRaw(kk_path_pathString(resultRaw))
        defer {
            try? FileManager.default.removeItem(atPath: createdPath)
        }

        var isDirectory: ObjCBool = false
        XCTAssertEqual(thrown, 0)
        XCTAssertTrue(createdPath.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertTrue((createdPath as NSString).lastPathComponent.hasPrefix("kswiftk-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdPath, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testPathCreateTempDirectoryPrefixAttributesUsesDefaultPrefixForNull() throws {
        var thrown = 0
        let resultRaw = kk_path_createTempDirectory_prefix_attributes(0, 0, &thrown)
        let createdPath = extractStringRaw(kk_path_pathString(resultRaw))
        defer {
            try? FileManager.default.removeItem(atPath: createdPath)
        }

        var isDirectory: ObjCBool = false
        XCTAssertEqual(thrown, 0)
        XCTAssertTrue((createdPath as NSString).lastPathComponent.hasPrefix("tmp"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdPath, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    private func makeRuntimeString(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }

    private func extractStringRaw(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
