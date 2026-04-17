import Foundation
@testable import Runtime
import XCTest

/// Tests for STDLIB-031-ABI-002: HexFormat number prefix/suffix encode/decode.
final class RuntimeHexFormatNumberPrefixSuffixTests: IsolatedRuntimeXCTestCase {

    // MARK: - Helpers

    private func makeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func toString(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func makeFormat(prefix: String = "", suffix: String = "", removeLeadingZeros: Bool = false) -> Int {
        let fmt = kk_hexformat_default()
        let prefixRaw = makeString(prefix)
        let suffixRaw = makeString(suffix)
        _ = kk_hexformat_prefix(fmt, prefixRaw)
        _ = kk_hexformat_suffix(fmt, suffixRaw)
        if removeLeadingZeros {
            guard let box = UnsafeMutableRawPointer(bitPattern: fmt).flatMap({ ptr in
                Runtime.tryCast(ptr, to: RuntimeHexFormatBox.self)
            }) else { return fmt }
            box.removeLeadingZeros = true
        }
        return fmt
    }

    // MARK: - Encode: prefix applied

    func testEncodeIntWithPrefixProducesExpectedString() {
        let fmt = makeFormat(prefix: "0x")
        let result = toString(kk_int_toHexString(255, fmt))
        XCTAssertEqual(result, "0x000000ff")
    }

    func testEncodeIntWithSuffixProducesExpectedString() {
        let fmt = makeFormat(suffix: "h")
        let result = toString(kk_int_toHexString(255, fmt))
        XCTAssertEqual(result, "000000ffh")
    }

    func testEncodeIntWithPrefixAndSuffixProducesExpectedString() {
        let fmt = makeFormat(prefix: "0x", suffix: "h")
        let result = toString(kk_int_toHexString(255, fmt))
        XCTAssertEqual(result, "0x000000ffh")
    }

    // MARK: - Round-trip: "0xFF"

    func testRoundTripIntWithHexPrefix() {
        let fmt = makeFormat(prefix: "0x", removeLeadingZeros: true)
        let encoded = toString(kk_int_toHexString(255, fmt))
        XCTAssertEqual(encoded, "0xff", "Encoding 255 with prefix 0x and removeLeadingZeros should give 0xff")

        var thrown = 0
        let decoded = kk_string_hexToInt(makeString(encoded), fmt, &thrown)
        XCTAssertEqual(thrown, 0, "Decoding 0xff should not throw")
        XCTAssertEqual(decoded, 255, "Round-trip of 255 via 0xff should give 255")
    }

    func testRoundTripIntUpperCase() {
        let fmt = kk_hexformat_default()
        guard let box = UnsafeMutableRawPointer(bitPattern: fmt).flatMap({ ptr in
            Runtime.tryCast(ptr, to: RuntimeHexFormatBox.self)
        }) else {
            XCTFail("Could not get format box")
            return
        }
        box.upperCase = true
        box.numberPrefix = "0x"
        box.removeLeadingZeros = true

        let encoded = toString(kk_int_toHexString(255, fmt))
        XCTAssertEqual(encoded, "0xFF")

        var thrown = 0
        let decoded = kk_string_hexToInt(makeString(encoded), fmt, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(decoded, 255)
    }

    // MARK: - Decode: missing prefix throws NumberFormatException

    func testDecodeIntMissingPrefixThrowsNumberFormatException() {
        let fmt = makeFormat(prefix: "0x")
        var thrown = 0
        _ = kk_string_hexToInt(makeString("ff"), fmt, &thrown)
        XCTAssertNotEqual(thrown, 0, "Missing prefix should throw NumberFormatException")

        // Verify the throwable message contains useful context
        if let throwPtr = UnsafeMutableRawPointer(bitPattern: thrown),
           let throwBox = Runtime.tryCast(throwPtr, to: RuntimeThrowableBox.self)
        {
            XCTAssertTrue(
                throwBox.message.contains("prefix"),
                "Exception message should mention prefix, got: \(throwBox.message)"
            )
        }
    }

    func testDecodeIntMissingSuffixThrowsNumberFormatException() {
        let fmt = makeFormat(suffix: "h")
        var thrown = 0
        _ = kk_string_hexToInt(makeString("ff"), fmt, &thrown)
        XCTAssertNotEqual(thrown, 0, "Missing suffix should throw NumberFormatException")
    }

    // MARK: - Decode: suffix ordering matters

    func testDecodeSuffixOrderIsEnforced() {
        // "h" suffix: "ff" (no suffix) must throw, "ffh" (with suffix) must succeed
        let fmt = makeFormat(suffix: "h")
        var thrown1 = 0
        _ = kk_string_hexToInt(makeString("ff"), fmt, &thrown1)
        XCTAssertNotEqual(thrown1, 0, "Missing suffix 'h' should throw")

        var thrown2 = 0
        let value = kk_string_hexToInt(makeString("ffh"), fmt, &thrown2)
        XCTAssertEqual(thrown2, 0, "Valid suffix 'h' should not throw")
        XCTAssertEqual(value, 255)
    }

    func testDecodePrefixThenSuffixOrder() {
        // prefix "0x", suffix "h": "0xffh" succeeds, "ffh" fails (missing prefix)
        let fmt = makeFormat(prefix: "0x", suffix: "h")
        var thrown1 = 0
        _ = kk_string_hexToInt(makeString("ffh"), fmt, &thrown1)
        XCTAssertNotEqual(thrown1, 0, "Missing prefix '0x' when suffix present should throw")

        var thrown2 = 0
        let value = kk_string_hexToInt(makeString("0xffh"), fmt, &thrown2)
        XCTAssertEqual(thrown2, 0, "Full prefix+suffix match should not throw")
        XCTAssertEqual(value, 255)
    }

    // MARK: - Default format (no prefix/suffix) still works

    func testDecodeIntDefaultFormatNoThrow() {
        let fmt = kk_hexformat_default()
        var thrown = 0
        let value = kk_string_hexToInt(makeString("ff"), fmt, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(value, 255)
    }

    // MARK: - Long encode/decode with prefix

    func testRoundTripLongWithPrefix() {
        let fmt = kk_hexformat_default()
        guard let box = UnsafeMutableRawPointer(bitPattern: fmt).flatMap({ ptr in
            Runtime.tryCast(ptr, to: RuntimeHexFormatBox.self)
        }) else {
            XCTFail("Could not get format box")
            return
        }
        box.numberPrefix = "0x"
        box.removeLeadingZeros = true

        let longRaw = kk_box_long(255)
        let encoded = toString(kk_long_toHexString(longRaw, fmt))
        XCTAssertEqual(encoded, "0xff")

        var thrown = 0
        let decoded = kk_string_hexToLong(makeString(encoded), fmt, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_unbox_long(decoded), 255)
    }

    func testDecodeLongMissingPrefixThrows() {
        let fmt = makeFormat(prefix: "0x")
        var thrown = 0
        _ = kk_string_hexToLong(makeString("ff"), fmt, &thrown)
        XCTAssertNotEqual(thrown, 0, "Missing prefix on long decode should throw")
    }
}
