@testable import Runtime
import XCTest

// STDLIB-573/574: Tests for String.encodeToByteArray() and ByteArray.decodeToString()

final class RuntimeEncodeDecodeTests: IsolatedRuntimeXCTestCase {

    // MARK: - Helpers

    private func makeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func extractSwiftString(_ raw: Int) -> String? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
        return extractString(from: ptr)
    }

    private func extractListElements(_ raw: Int) -> [Int]? {
        runtimeListBox(from: raw)?.elements
    }

    private func makeListRaw(_ elements: [Int]) -> Int {
        let box = RuntimeListBox(elements: elements)
        return registerRuntimeObject(box)
    }

    // MARK: - encodeToByteArray: basic ASCII round-trip

    func testEncodeToByteArrayASCII() {
        let strRaw = makeString("Hello")
        let result = kk_string_encodeToByteArray(strRaw)
        let elements = extractListElements(result)
        // "Hello" -> [72, 101, 108, 108, 111]
        XCTAssertEqual(elements, [72, 101, 108, 108, 111])
    }

    // MARK: - encodeToByteArray: non-ASCII (multi-byte UTF-8)

    func testEncodeToByteArrayNonASCII() {
        let strRaw = makeString("\u{00E9}") // e-acute (U+00E9), UTF-8: [0xC3, 0xA9]
        let result = kk_string_encodeToByteArray(strRaw)
        let elements = extractListElements(result)
        XCTAssertEqual(elements, [0xC3, 0xA9])
    }

    // MARK: - encodeToByteArray matches toByteArray

    func testEncodeToByteArrayMatchesToByteArray() {
        let strRaw = makeString("test123")
        let encode = kk_string_encodeToByteArray(strRaw)
        let toByte = kk_string_toByteArray(strRaw)
        let encodeElems = extractListElements(encode)
        let toByteElems = extractListElements(toByte)
        XCTAssertEqual(encodeElems, toByteElems,
                       "encodeToByteArray and toByteArray should produce identical results")
    }

    // MARK: - decodeToString: basic ASCII round-trip

    func testDecodeToStringASCII() {
        let byteArray = makeListRaw([72, 101, 108, 108, 111]) // "Hello"
        let result = kk_bytearray_decodeToString(byteArray)
        XCTAssertEqual(extractSwiftString(result), "Hello")
    }

    // MARK: - decodeToString: non-ASCII (multi-byte UTF-8)

    func testDecodeToStringNonASCII() {
        // U+00E9 (e-acute) -> UTF-8: [0xC3, 0xA9]
        let byteArray = makeListRaw([0xC3, 0xA9])
        let result = kk_bytearray_decodeToString(byteArray)
        XCTAssertEqual(extractSwiftString(result), "\u{00E9}")
    }

    // MARK: - Full round-trip: encode then decode

    func testRoundTripUTF8() {
        let original = "Hello, World! \u{1F600}" // includes emoji (4-byte UTF-8)
        let strRaw = makeString(original)
        let encoded = kk_string_encodeToByteArray(strRaw)
        let decoded = kk_bytearray_decodeToString(encoded)
        XCTAssertEqual(extractSwiftString(decoded), original)
    }

    // MARK: - decodeToString: negative byte values (truncating semantics)

    func testDecodeToStringNegativeBytes() {
        // In Kotlin, ByteArray stores signed bytes. -1 should become 0xFF (255).
        // [0xC3, 0xA9] encodes U+00E9 — test using negative representations.
        // -61 truncated to UInt8 = 195 = 0xC3; -87 truncated to UInt8 = 169 = 0xA9
        let byteArray = makeListRaw([-61, -87])
        let result = kk_bytearray_decodeToString(byteArray)
        XCTAssertEqual(extractSwiftString(result), "\u{00E9}")
    }

    // MARK: - decodeToString: malformed UTF-8 uses replacement character

    func testDecodeToStringMalformedUTF8() {
        // 0xFF is not valid in UTF-8 — should produce replacement character U+FFFD
        let byteArray = makeListRaw([0xFF])
        let result = kk_bytearray_decodeToString(byteArray)
        let decoded = extractSwiftString(result)
        XCTAssertNotNil(decoded)
        XCTAssertTrue(decoded?.contains("\u{FFFD}") == true,
                      "Malformed UTF-8 should produce replacement character, got: \(decoded ?? "nil")")
    }

    // MARK: - decodeToString: empty array

    func testDecodeToStringEmptyArray() {
        let byteArray = makeListRaw([])
        let result = kk_bytearray_decodeToString(byteArray)
        XCTAssertEqual(extractSwiftString(result), "")
    }

    // MARK: - encodeToByteArray: empty string

    func testEncodeToByteArrayEmptyString() {
        let strRaw = makeString("")
        let result = kk_string_encodeToByteArray(strRaw)
        XCTAssertEqual(extractListElements(result), [])
    }
}
