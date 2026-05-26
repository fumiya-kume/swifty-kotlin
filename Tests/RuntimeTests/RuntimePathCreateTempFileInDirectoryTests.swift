import Foundation
@testable import Runtime
import XCTest

final class RuntimePathCreateTempFileInDirectoryTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    func testPathCreateTempFileDirectoryPrefixSuffixAttributesCreatesFileInParent() throws {
        let parentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: parentURL)
        }
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        var thrown = 0
        let resultRaw = kk_path_createTempFile_directory_prefix_suffix_attributes(
            runtimeTestPathHandle(parentURL.path),
            makeRuntimeString("kswiftk-"),
            makeRuntimeString(".data"),
            0,
            &thrown
        )
        let createdPath = try XCTUnwrap(runtimePathString(resultRaw))

        XCTAssertEqual(thrown, 0)
        XCTAssertTrue(createdPath.hasPrefix(parentURL.path))
        XCTAssertTrue((createdPath as NSString).lastPathComponent.hasPrefix("kswiftk-"))
        XCTAssertTrue(createdPath.hasSuffix(".data"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdPath))
    }

    func testPathCreateTempFileDirectoryPrefixSuffixAttributesUsesDefaultsForNulls() throws {
        var thrown = 0
        let resultRaw = kk_path_createTempFile_directory_prefix_suffix_attributes(0, 0, 0, 0, &thrown)
        let createdPath = try XCTUnwrap(runtimePathString(resultRaw))
        defer {
            try? FileManager.default.removeItem(atPath: createdPath)
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertTrue(createdPath.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertTrue((createdPath as NSString).lastPathComponent.hasPrefix("tmp"))
        XCTAssertTrue(createdPath.hasSuffix(".tmp"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdPath))
    }

    private func runtimePathString(_ raw: Int) -> String? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimePathBox.self) else {
            return nil
        }
        return box.pathString
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
