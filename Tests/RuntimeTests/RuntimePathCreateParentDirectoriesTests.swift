import Foundation
@testable import Runtime
import XCTest

final class RuntimePathCreateParentDirectoriesTests: IsolatedRuntimeXCTestCase {
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
    func testPathCreateParentDirectoriesAttributesCreatesOnlyParentTree() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = rootURL.appendingPathComponent("a").appendingPathComponent("b").appendingPathComponent("file.txt")
        let parentURL = fileURL.deletingLastPathComponent()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        var thrown = 0
        let pathRaw = runtimeTestPathHandle(fileURL.path)
        let resultRaw = kk_path_createParentDirectories_attributes(pathRaw, 0, &thrown)

        var isDirectory: ObjCBool = false
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(resultRaw, pathRaw)
        XCTAssertTrue(FileManager.default.fileExists(atPath: parentURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testPathCreateParentDirectoriesAttributesFailsWhenParentIsFile() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let parentFileURL = rootURL.appendingPathComponent("parent-file")
        let childURL = parentFileURL.appendingPathComponent("child.txt")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("parent".utf8).write(to: parentFileURL)

        var thrown = 0
        let pathRaw = runtimeTestPathHandle(childURL.path)
        let resultRaw = kk_path_createParentDirectories_attributes(pathRaw, 0, &thrown)

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(resultRaw, pathRaw)
        XCTAssertEqual(try String(contentsOf: parentFileURL, encoding: .utf8), "parent")
        XCTAssertFalse(FileManager.default.fileExists(atPath: childURL.path))
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
