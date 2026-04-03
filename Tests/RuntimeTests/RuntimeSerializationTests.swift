@testable import Runtime
import Foundation
import XCTest

final class RuntimeSerializationTests: IsolatedRuntimeXCTestCase {
    private func makeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func extractSwiftString(_ raw: Int) -> String? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
            return nil
        }
        return extractString(from: ptr)
    }

    private func jsonObject(from raw: Int) throws -> Any {
        let string = try XCTUnwrap(extractSwiftString(raw))
        let data = try XCTUnwrap(string.data(using: .utf8))
        return try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
    }

    func testEncodeMapProducesJSONObject() throws {
        let json = kk_json_default()
        let mapRaw = registerRuntimeObject(RuntimeMapBox(
            keys: [makeString("name"), makeString("age"), makeString("active")],
            values: [makeString("Alice"), makeString("30"), makeString("true")]
        ))

        let encoded = kk_json_encodeToString(json, mapRaw)
        let object = try XCTUnwrap(try jsonObject(from: encoded) as? [String: String])

        XCTAssertEqual(object["name"], "Alice")
        XCTAssertEqual(object["age"], "30")
        XCTAssertEqual(object["active"], "true")
    }

    func testEncodeListProducesJSONArray() throws {
        let json = kk_json_default()
        let listRaw = registerRuntimeObject(RuntimeListBox(elements: [
            makeString("a"),
            makeString("b"),
            makeString("c"),
        ]))

        let encoded = kk_json_encodeToString(json, listRaw)
        let array = try XCTUnwrap(try jsonObject(from: encoded) as? [String])
        XCTAssertEqual(array, ["a", "b", "c"])
    }

    func testDecodeObjectReturnsRuntimeMap() {
        let json = kk_json_default()
        var thrown = 0
        let decoded = kk_json_decodeFromString(
            json,
            makeString("{\"greeting\":\"hello\",\"count\":\"42\"}"),
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        let map = runtimeMapBox(from: decoded)
        XCTAssertNotNil(map)
        XCTAssertEqual(map?.keys.count, 2)
        XCTAssertEqual(map?.values.count, 2)

        let entries: [(String, String)] = zip(map?.keys ?? [], map?.values ?? []).compactMap { key, value in
            guard let k = extractSwiftString(key), let v = extractSwiftString(value) else {
                return nil
            }
            return (k, v)
        }
        let decodedDict = Dictionary(uniqueKeysWithValues: entries)
        XCTAssertEqual(decodedDict, ["greeting": "hello", "count": "42"])
    }

    func testDecodeArrayReturnsRuntimeList() {
        let json = kk_json_default()
        var thrown = 0
        let decoded = kk_json_decodeFromString(
            json,
            makeString("[\"x\",\"y\",\"z\"]"),
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        let list = runtimeListBox(from: decoded)
        XCTAssertEqual(list?.elements.compactMap(extractSwiftString), ["x", "y", "z"])
    }

    func testDecodeInvalidJSONSetsThrowable() {
        let json = kk_json_default()
        var thrown = 0
        let decoded = kk_json_decodeFromString(
            json,
            makeString("{invalid"),
            &thrown
        )

        XCTAssertEqual(decoded, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
    }

    func testEncodeSetUsesJSONArrayRepresentation() throws {
        let json = kk_json_default()
        let setRaw = registerRuntimeObject(RuntimeSetBox(elements: [
            makeString("left"),
            makeString("right"),
        ]))

        let encoded = kk_json_encodeToString(json, setRaw)
        let array = try XCTUnwrap(try jsonObject(from: encoded) as? [String])
        XCTAssertEqual(array, ["left", "right"])
    }
}
