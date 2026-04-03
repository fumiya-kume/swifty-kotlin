import Foundation
@testable import Runtime
import XCTest

final class RuntimeResourceBundleTests: IsolatedRuntimeXCTestCase {
    func testResourceBundleLoadsLocaleSpecificProperties() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            unsetenv("KSWIFTK_RESOURCE_ROOT")
            try? FileManager.default.removeItem(at: dir)
        }

        try "greeting=こんにちは\nfarewell=さようなら\n".write(
            to: dir.appendingPathComponent("messages_ja_JP.properties"),
            atomically: true,
            encoding: .utf8
        )
        setenv("KSWIFTK_RESOURCE_ROOT", dir.path, 1)

        let locale = kk_locale_new(runtimeString("ja_JP"))
        var thrown = 0
        let bundle = kk_resource_bundle_getBundle(runtimeString("messages"), locale, &thrown)
        XCTAssertEqual(thrown, 0)
        let greeting = kk_resource_bundle_getString(bundle, runtimeString("greeting"), &thrown)
        XCTAssertEqual(stringValue(greeting), "こんにちは")
        let keys = runtimeListBox(from: kk_resource_bundle_getKeys(bundle))?.elements.compactMap { extractString(from: UnsafeMutableRawPointer(bitPattern: $0)) } ?? []
        XCTAssertEqual(keys, ["farewell", "greeting"])
    }

    func testResourceBundleFallsBackToParentBundlesAndGetObject() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            unsetenv("KSWIFTK_RESOURCE_ROOT")
            try? FileManager.default.removeItem(at: dir)
        }

        try "greeting=Hello\nbaseOnly=Base\n".write(
            to: dir.appendingPathComponent("messages.properties"),
            atomically: true,
            encoding: .utf8
        )
        try "greeting=こんにちは\njaOnly=日本語\n".write(
            to: dir.appendingPathComponent("messages_ja.properties"),
            atomically: true,
            encoding: .utf8
        )
        try "jpOnly=日本\n".write(
            to: dir.appendingPathComponent("messages_ja_JP.properties"),
            atomically: true,
            encoding: .utf8
        )
        setenv("KSWIFTK_RESOURCE_ROOT", dir.path, 1)

        let locale = kk_locale_new(runtimeString("ja_JP"))
        var thrown = 0
        let bundle = kk_resource_bundle_getBundle(runtimeString("messages"), locale, &thrown)
        XCTAssertEqual(thrown, 0)

        let greeting = kk_resource_bundle_getString(bundle, runtimeString("greeting"), &thrown)
        XCTAssertEqual(stringValue(greeting), "こんにちは")

        let baseOnly = kk_resource_bundle_getString(bundle, runtimeString("baseOnly"), &thrown)
        XCTAssertEqual(stringValue(baseOnly), "Base")

        let objectValue = kk_resource_bundle_getObject(bundle, runtimeString("jpOnly"), &thrown)
        XCTAssertEqual(stringValue(objectValue), "日本")

        let keys = runtimeListBox(from: kk_resource_bundle_getKeys(bundle))?.elements.compactMap { extractString(from: UnsafeMutableRawPointer(bitPattern: $0)) } ?? []
        XCTAssertEqual(keys, ["baseOnly", "greeting", "jaOnly", "jpOnly"])
    }

    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func stringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
