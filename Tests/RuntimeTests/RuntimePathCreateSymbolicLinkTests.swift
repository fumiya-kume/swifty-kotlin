import Foundation
@testable import Runtime
import XCTest

final class RuntimePathCreateSymbolicLinkTests: IsolatedRuntimeXCTestCase {
    func testPathCreateSymbolicLinkPointingToAttributesCreatesLink() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let targetURL = rootURL.appendingPathComponent("target.txt")
        let linkURL = rootURL.appendingPathComponent("link.txt")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("target".utf8).write(to: targetURL)

        var thrown = 0
        let linkRaw = runtimeTestPathHandle(linkURL.path)
        let targetRaw = runtimeTestPathHandle(targetURL.path)
        let resultRaw = kk_path_createSymbolicLinkPointingTo_attributes(linkRaw, targetRaw, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(resultRaw, linkRaw)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path), targetURL.path)
        XCTAssertEqual(try String(contentsOf: linkURL, encoding: .utf8), "target")
    }

    func testPathCreateSymbolicLinkPointingToAttributesFailsWhenLinkExists() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let targetURL = rootURL.appendingPathComponent("target.txt")
        let linkURL = rootURL.appendingPathComponent("link.txt")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("target".utf8).write(to: targetURL)
        try Data("existing".utf8).write(to: linkURL)

        var thrown = 0
        let linkRaw = runtimeTestPathHandle(linkURL.path)
        let targetRaw = runtimeTestPathHandle(targetURL.path)
        let resultRaw = kk_path_createSymbolicLinkPointingTo_attributes(linkRaw, targetRaw, 0, &thrown)

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(resultRaw, linkRaw)
        XCTAssertEqual(try String(contentsOf: linkURL, encoding: .utf8), "existing")
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
