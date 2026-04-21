@testable import Runtime
import XCTest

/// Tests for the Base64 runtime ABI (STDLIB-031-ABI-001).
///
/// RFC 4648 test vectors are taken from §10 of the spec:
///   ""       → ""
///   "f"      → "Zg=="
///   "fo"     → "Zm8="
///   "foo"    → "Zm9v"
///   "foob"   → "Zm9vYg=="
///   "fooba"  → "Zm9vYmE="
///   "foobar" → "Zm9vYmFy"
final class RuntimeBase64Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeByteArray(_ bytes: [UInt8]) -> Int {
        let intElements = bytes.map { Int(Int8(bitPattern: $0)) }
        return registerRuntimeObject(RuntimeListBox(elements: intElements))
    }

    private func makeByteArrayFromString(_ s: String) -> Int {
        makeByteArray(Array(s.utf8))
    }

    private func runtimeString(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self) else { return "" }
        return box.value
    }

    private func makeRuntimeString(_ s: String) -> Int {
        let utf8 = Array(s.utf8)
        if utf8.isEmpty {
            var nul: UInt8 = 0
            return Int(bitPattern: kk_string_from_utf8(&nul, 0))
        }
        return utf8.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return 0 }
            return Int(bitPattern: kk_string_from_utf8(base, Int32(buf.count)))
        }
    }

    private func byteArrayToUInt8s(_ raw: Int) -> [UInt8] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else { return [] }
        return box.elements.map { UInt8(truncatingIfNeeded: $0) }
    }

    // Padding option raw values (must match Base64PaddingOption in RuntimeBase64.swift)
    private let paddingPresent = 0
    private let paddingAbsent = 1
    private let paddingPresentOptional = 2
    private let paddingAbsentOptional = 3

    // MARK: - RFC 4648 §10 Test Vectors — Default (RFC 4648 §4)

    func testRFC4648VectorsEncodeDefault() {
        let vectors: [(String, String)] = [
            ("", ""),
            ("f", "Zg=="),
            ("fo", "Zm8="),
            ("foo", "Zm9v"),
            ("foob", "Zm9vYg=="),
            ("fooba", "Zm9vYmE="),
            ("foobar", "Zm9vYmFy"),
        ]
        for (input, expected) in vectors {
            let rawBytes = makeByteArrayFromString(input)
            let result = runtimeString(kk_base64_encode_default(rawBytes, paddingPresent))
            XCTAssertEqual(result, expected, "Encoding '\(input)' failed")
        }
    }

    func testRFC4648VectorsDecodeDefault() {
        let vectors: [(String, String)] = [
            ("", ""),
            ("Zg==", "f"),
            ("Zm8=", "fo"),
            ("Zm9v", "foo"),
            ("Zm9vYg==", "foob"),
            ("Zm9vYmE=", "fooba"),
            ("Zm9vYmFy", "foobar"),
        ]
        for (input, expected) in vectors {
            var thrown = 0
            let resultRaw = kk_base64_decode_default(makeRuntimeString(input), paddingPresentOptional, &thrown)
            XCTAssertEqual(thrown, 0, "Unexpected throw for input '\(input)'")
            let bytes = byteArrayToUInt8s(resultRaw)
            let decoded = String(bytes: bytes, encoding: .utf8) ?? ""
            XCTAssertEqual(decoded, expected, "Decoding '\(input)' failed")
        }
    }

    // MARK: - PaddingOption.PRESENT

    func testPaddingPresentEncodesWithPad() {
        let raw = makeByteArrayFromString("fo")
        let result = runtimeString(kk_base64_encode_default(raw, paddingPresent))
        XCTAssertEqual(result, "Zm8=")
    }

    func testPaddingPresentRejectsMissingPadding() {
        var thrown = 0
        _ = kk_base64_decode_default(makeRuntimeString("Zm8"), paddingPresent, &thrown)
        XCTAssertNotEqual(thrown, 0, "Should throw on missing padding when PRESENT")
    }

    // MARK: - PaddingOption.ABSENT

    func testPaddingAbsentEncodesWithoutPad() {
        let raw = makeByteArrayFromString("fo")
        let result = runtimeString(kk_base64_encode_default(raw, paddingAbsent))
        XCTAssertEqual(result, "Zm8")
    }

    func testPaddingAbsentRejectsPadding() {
        var thrown = 0
        _ = kk_base64_decode_default(makeRuntimeString("Zm8="), paddingAbsent, &thrown)
        XCTAssertNotEqual(thrown, 0, "Should throw on padding when ABSENT")
    }

    func testPaddingAbsentDecodeRoundTrip() {
        let input = "foobar"
        let rawBytes = makeByteArrayFromString(input)
        let encoded = runtimeString(kk_base64_encode_default(rawBytes, paddingAbsent))
        XCTAssertFalse(encoded.contains("="), "Should have no padding")

        var thrown = 0
        let decoded = byteArrayToUInt8s(kk_base64_decode_default(makeRuntimeString(encoded), paddingAbsent, &thrown))
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(String(bytes: decoded, encoding: .utf8), input)
    }

    // MARK: - PaddingOption.PRESENT_OPTIONAL

    func testPaddingPresentOptionalEncodeHasPad() {
        let raw = makeByteArrayFromString("fo")
        let result = runtimeString(kk_base64_encode_default(raw, paddingPresentOptional))
        XCTAssertEqual(result, "Zm8=")
    }

    func testPaddingPresentOptionalDecodeAcceptsBothForms() {
        for padded in ["Zm8=", "Zm8"] {
            var thrown = 0
            let bytes = byteArrayToUInt8s(kk_base64_decode_default(makeRuntimeString(padded), paddingPresentOptional, &thrown))
            XCTAssertEqual(thrown, 0, "Should not throw for '\(padded)'")
            XCTAssertEqual(String(bytes: bytes, encoding: .utf8), "fo")
        }
    }

    // MARK: - PaddingOption.ABSENT_OPTIONAL

    func testPaddingAbsentOptionalEncodeNoPad() {
        let raw = makeByteArrayFromString("fo")
        let result = runtimeString(kk_base64_encode_default(raw, paddingAbsentOptional))
        XCTAssertEqual(result, "Zm8")
    }

    func testPaddingAbsentOptionalDecodeAcceptsBothForms() {
        for padded in ["Zm8=", "Zm8"] {
            var thrown = 0
            let bytes = byteArrayToUInt8s(kk_base64_decode_default(makeRuntimeString(padded), paddingAbsentOptional, &thrown))
            XCTAssertEqual(thrown, 0, "Should not throw for '\(padded)'")
            XCTAssertEqual(String(bytes: bytes, encoding: .utf8), "fo")
        }
    }

    // MARK: - URL-safe Alphabet (-_)

    func testUrlSafeEncodeUsesUrlAlphabet() {
        // Produce a byte sequence that generates + and / in standard base64
        // 0xFB 0xEF 0xBE → "+/++" in standard, "-_-+" in url-safe (no pad for length 3)
        let bytes: [UInt8] = [0xFB, 0xEF, 0xBE]
        let raw = makeByteArray(bytes)
        let result = runtimeString(kk_base64_encode_urlsafe(raw, paddingAbsent))
        XCTAssertFalse(result.contains("+"), "URL-safe must not contain '+'")
        XCTAssertFalse(result.contains("/"), "URL-safe must not contain '/'")
        XCTAssertTrue(result.contains("-") || result.contains("_"), "URL-safe must use - or _")
    }

    func testUrlSafeRoundTrip() {
        let input = "Hello, World! \u{1F30D}"
        let rawBytes = makeByteArrayFromString(input)
        let encoded = runtimeString(kk_base64_encode_urlsafe(rawBytes, paddingAbsentOptional))
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))

        var thrown = 0
        let decoded = byteArrayToUInt8s(kk_base64_decode_urlsafe(makeRuntimeString(encoded), paddingAbsentOptional, &thrown))
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(String(bytes: decoded, encoding: .utf8), input)
    }

    func testUrlSafeDecodeRejectsStandardChars() {
        // "+" and "/" are not valid URL-safe alphabet characters
        var thrown = 0
        _ = kk_base64_decode_urlsafe(makeRuntimeString("Zm9v+w=="), paddingPresentOptional, &thrown)
        XCTAssertNotEqual(thrown, 0, "URL-safe decode should reject standard-alphabet '+'")
    }

    // MARK: - MIME (RFC 2045)

    func testMimeEncodeInsertsCRLF() {
        // Use 60 bytes so the output exceeds 76 characters (80 base64 chars)
        let bytes = [UInt8](repeating: 0xAB, count: 60)
        let raw = makeByteArray(bytes)
        let result = runtimeString(kk_base64_encode_mime(raw, paddingPresent))
        XCTAssertTrue(result.contains("\r\n"), "MIME output must contain CRLF")
        let lines = result.components(separatedBy: "\r\n")
        for line in lines where !line.isEmpty {
            XCTAssertLessThanOrEqual(line.count, 76, "MIME line must be <= 76 chars")
        }
    }

    func testMimeDecodeToleratesWhitespace() {
        // Manually build a MIME-formatted string with CRLF
        let input = "Zm9v\r\nYmFy"
        var thrown = 0
        let decoded = byteArrayToUInt8s(kk_base64_decode_mime(makeRuntimeString(input), paddingPresentOptional, &thrown))
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(String(bytes: decoded, encoding: .utf8), "foobar")
    }

    func testMimeRoundTrip() {
        let input = String(repeating: "KSwiftK", count: 12)
        let rawBytes = makeByteArrayFromString(input)
        let encoded = runtimeString(kk_base64_encode_mime(rawBytes, paddingPresent))
        var thrown = 0
        let decoded = byteArrayToUInt8s(kk_base64_decode_mime(makeRuntimeString(encoded), paddingPresentOptional, &thrown))
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(String(bytes: decoded, encoding: .utf8), input)
    }

    // MARK: - encodeToByteArray

    func testEncodeToByteArrayDefaultProducesAsciiBytes() {
        let raw = makeByteArrayFromString("foo")
        let result = byteArrayToUInt8s(kk_base64_encodeToByteArray_default(raw, paddingPresent))
        XCTAssertEqual(String(bytes: result, encoding: .utf8), "Zm9v")
    }

    func testEncodeToByteArrayUrlSafe() {
        let bytes: [UInt8] = [0xFB, 0xEF, 0xBE]
        let raw = makeByteArray(bytes)
        let result = byteArrayToUInt8s(kk_base64_encodeToByteArray_urlsafe(raw, paddingAbsent))
        XCTAssertFalse(result.contains(UInt8(ascii: "+")))
        XCTAssertFalse(result.contains(UInt8(ascii: "/")))
    }

    func testEncodeToByteArrayMimeContainsCRLF() {
        let bytes = [UInt8](repeating: 0xCC, count: 60)
        let raw = makeByteArray(bytes)
        let result = byteArrayToUInt8s(kk_base64_encodeToByteArray_mime(raw, paddingPresent))
        let str = String(bytes: result, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("\r\n"))
    }

    // MARK: - Error cases

    func testDecodeInvalidCharacterThrows() {
        var thrown = 0
        _ = kk_base64_decode_default(makeRuntimeString("!!!@"), paddingPresentOptional, &thrown)
        XCTAssertNotEqual(thrown, 0, "Should throw on invalid base64 characters")
    }

    func testDecodeEmptyStringReturnsEmptyByteArray() {
        var thrown = 0
        let result = byteArrayToUInt8s(kk_base64_decode_default(makeRuntimeString(""), paddingPresentOptional, &thrown))
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, [])
    }

    // MARK: - PaddingOption constant ABI

    func testPaddingOptionConstantValues() {
        XCTAssertEqual(kk_base64_padding_present(), 0)
        XCTAssertEqual(kk_base64_padding_absent(), 1)
        XCTAssertEqual(kk_base64_padding_present_optional(), 2)
        XCTAssertEqual(kk_base64_padding_absent_optional(), 3)
    }
}
