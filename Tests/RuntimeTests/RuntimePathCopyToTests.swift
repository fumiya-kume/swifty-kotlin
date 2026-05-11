import Foundation
@testable import Runtime
import XCTest

final class RuntimePathCopyToTests: IsolatedRuntimeXCTestCase {
    func testPathCopyToOptionsCopiesFileAndReturnsTargetPath() throws {
        let sourceURL = try makeTempFile(contents: "copy me")
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }

        let sourceRaw = runtimeTestPathHandle(sourceURL.path)
        let targetRaw = runtimeTestPathHandle(targetURL.path)
        var thrown = 0
        let resultRaw = kk_path_copyTo_options(sourceRaw, targetRaw, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(resultRaw, targetRaw)
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "copy me")
    }

    func testPathCopyToOptionsReportsCopyFailure() throws {
        let sourceURL = try makeTempFile(contents: "source")
        let targetURL = try makeTempFile(contents: "existing")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: targetURL)
        }

        let sourceRaw = runtimeTestPathHandle(sourceURL.path)
        let targetRaw = runtimeTestPathHandle(targetURL.path)
        var thrown = 0
        let resultRaw = kk_path_copyTo_options(sourceRaw, targetRaw, 0, &thrown)

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(resultRaw, targetRaw)
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "existing")
    }

    private func makeTempFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
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
