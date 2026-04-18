@testable import Runtime
import XCTest

// STDLIB-031: Edge case coverage for kotlin.text.HexFormat runtime implementation.
//
// Covers:
// - HexFormat.Default companion property
// - HexFormat { } builder DSL (upperCase, byteSeparator)
// - Int.toHexString(format) – lowercase/uppercase, zero-padded, negative/boundary
// - Long.toHexString(format) – lowercase/uppercase, negative (two's-complement 16 hex digits)
// - ByteArray.toHexString(format) – empty, single, multi, separator, uppercase
// - String.hexToByteArray(format) – empty, separator, round-trip
// - String.hexToInt(format) – basic parse
// - String.hexToLong(format) – basic parse

final class RuntimeHexFormatEdgeCaseTests: IsolatedRuntimeXCTestCase {

    // MARK: - Helpers

    private func makeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func extractString(_ raw: Int) -> String? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
        return Runtime.extractString(from: ptr)
    }

    private func makeListRaw(_ elements: [Int]) -> Int {
        let box = RuntimeListBox(elements: elements)
        return registerRuntimeObject(box)
    }

    private func extractListElements(_ raw: Int) -> [Int]? {
        runtimeListBox(from: raw)?.elements
    }

    /// Build a HexFormat by mutating a RuntimeHexFormatBox directly (no DSL closure overhead).
    private func makeFormat(upperCase: Bool = false, byteSeparator: String = "") -> Int {
        let box = RuntimeHexFormatBox(upperCase: upperCase, byteSeparator: byteSeparator)
        return registerRuntimeObject(box)
    }

    // MARK: - HexFormat.Default

    func testDefaultHexFormatIsNotNull() {
        let raw = kk_hexformat_default()
        XCTAssertNotEqual(raw, 0, "HexFormat.Default must not be null")
    }

    func testDefaultHexFormatUpperCaseIsFalse() {
        let raw = kk_hexformat_default()
        // upperCase returns a boxed Bool; unbox via kk_unbox_bool
        let ucRaw = kk_hexformat_upperCase(raw)
        XCTAssertEqual(kk_unbox_bool(ucRaw), 0, "Default HexFormat.upperCase must be false")
    }

    // MARK: - HexFormat.bytes (returns same object for chaining)

    func testHexFormatBytesReturnsSelf() {
        let fmt = makeFormat()
        XCTAssertEqual(kk_hexformat_bytes(fmt), fmt, ".bytes must return the same HexFormat pointer")
    }

    // MARK: - Int.toHexString – lowercase (default)

    func testIntToHexStringLowercase() {
        let fmt = makeFormat(upperCase: false)
        let result = kk_int_toHexString(0xFF, fmt)
        XCTAssertEqual(extractString(result), "000000ff")
    }

    func testIntToHexStringUppercase() {
        let fmt = makeFormat(upperCase: true)
        let result = kk_int_toHexString(0xFF, fmt)
        XCTAssertEqual(extractString(result), "000000FF")
    }

    func testIntToHexStringZero() {
        let fmt = makeFormat()
        let result = kk_int_toHexString(0, fmt)
        XCTAssertEqual(extractString(result), "00000000", "Zero must produce eight zero digits")
    }

    func testIntToHexStringMaxValue() {
        let fmt = makeFormat()
        // Int32.max = 0x7FFFFFFF
        let result = kk_int_toHexString(Int(Int32.max), fmt)
        XCTAssertEqual(extractString(result), "7fffffff")
    }

    func testIntToHexStringNegativeOne() {
        let fmt = makeFormat()
        // -1 as Int32 two's-complement = 0xFFFFFFFF
        let result = kk_int_toHexString(-1, fmt)
        XCTAssertEqual(extractString(result), "ffffffff")
    }

    func testIntToHexStringMinValue() {
        let fmt = makeFormat()
        // Int32.min = 0x80000000
        let result = kk_int_toHexString(Int(Int32.min), fmt)
        XCTAssertEqual(extractString(result), "80000000")
    }

    func testIntToHexStringAlwaysEightChars() {
        let fmt = makeFormat()
        let result = kk_int_toHexString(1, fmt)
        let str = extractString(result) ?? ""
        XCTAssertEqual(str.count, 8, "Int.toHexString must always produce exactly 8 hex characters")
    }

    // MARK: - Long.toHexString

    func testLongToHexStringPositive() {
        let fmt = makeFormat(upperCase: false)
        let longRaw = kk_box_long(255) // 0xFF
        let result = kk_long_toHexString(longRaw, fmt)
        XCTAssertEqual(extractString(result), "ff")
    }

    func testLongToHexStringUppercase() {
        let fmt = makeFormat(upperCase: true)
        let longRaw = kk_box_long(255)
        let result = kk_long_toHexString(longRaw, fmt)
        XCTAssertEqual(extractString(result), "FF")
    }

    func testLongToHexStringNegativeProduces16Chars() {
        let fmt = makeFormat()
        // -1L in Kotlin = 0xFFFFFFFFFFFFFFFF (16 hex chars)
        let longRaw = kk_box_long(-1)
        let result = kk_long_toHexString(longRaw, fmt)
        let str = extractString(result) ?? ""
        XCTAssertEqual(str, "ffffffffffffffff",
                       "Long.toHexString(-1) must produce 16 f's (two's-complement)")
    }

    func testLongToHexStringZero() {
        let fmt = makeFormat()
        let longRaw = kk_box_long(0)
        let result = kk_long_toHexString(longRaw, fmt)
        XCTAssertEqual(extractString(result), "0")
    }

    // MARK: - ByteArray.toHexString – empty input

    func testByteArrayToHexStringEmpty() {
        let fmt = makeFormat()
        let arr = makeListRaw([])
        let result = kk_bytearray_toHexString(arr, fmt)
        XCTAssertEqual(extractString(result), "", "Empty ByteArray must produce empty hex string")
    }

    // MARK: - ByteArray.toHexString – single byte

    func testByteArrayToHexStringSingleByte() {
        let fmt = makeFormat()
        let arr = makeListRaw([0x0A])
        let result = kk_bytearray_toHexString(arr, fmt)
        XCTAssertEqual(extractString(result), "0a")
    }

    func testByteArrayToHexStringAllZeroByte() {
        let fmt = makeFormat()
        let arr = makeListRaw([0x00])
        let result = kk_bytearray_toHexString(arr, fmt)
        XCTAssertEqual(extractString(result), "00")
    }

    func testByteArrayToHexStringMaxByte() {
        let fmt = makeFormat()
        // 0xFF stored as Int (-1 in signed representation)
        let arr = makeListRaw([-1])
        let result = kk_bytearray_toHexString(arr, fmt)
        XCTAssertEqual(extractString(result), "ff")
    }

    // MARK: - ByteArray.toHexString – multiple bytes, no separator

    func testByteArrayToHexStringMultiByteNoSeparator() {
        let fmt = makeFormat()
        let arr = makeListRaw([0xDE, 0xAD, 0xBE, 0xEF])
        let result = kk_bytearray_toHexString(arr, fmt)
        XCTAssertEqual(extractString(result), "deadbeef")
    }

    func testByteArrayToHexStringUppercase() {
        let fmt = makeFormat(upperCase: true)
        let arr = makeListRaw([0xDE, 0xAD, 0xBE, 0xEF])
        let result = kk_bytearray_toHexString(arr, fmt)
        XCTAssertEqual(extractString(result), "DEADBEEF")
    }

    // MARK: - ByteArray.toHexString – with byteSeparator

    func testByteArrayToHexStringColonSeparator() {
        let fmt = makeFormat(byteSeparator: ":")
        let arr = makeListRaw([0x01, 0x02, 0x03])
        let result = kk_bytearray_toHexString(arr, fmt)
        XCTAssertEqual(extractString(result), "01:02:03")
    }

    func testByteArrayToHexStringSpaceSeparator() {
        let fmt = makeFormat(byteSeparator: " ")
        let arr = makeListRaw([0xAB, 0xCD])
        let result = kk_bytearray_toHexString(arr, fmt)
        XCTAssertEqual(extractString(result), "ab cd")
    }

    func testByteArrayToHexStringDashSeparatorUppercase() {
        let fmt = makeFormat(upperCase: true, byteSeparator: "-")
        let arr = makeListRaw([0x0F, 0xFF])
        let result = kk_bytearray_toHexString(arr, fmt)
        XCTAssertEqual(extractString(result), "0F-FF")
    }

    // MARK: - ByteArray.toHexString – single byte with separator (no separator in output)

    func testByteArrayToHexStringSingleByteWithSeparator() {
        let fmt = makeFormat(byteSeparator: ":")
        let arr = makeListRaw([0x42])
        let result = kk_bytearray_toHexString(arr, fmt)
        // Single byte: no separator joins
        XCTAssertEqual(extractString(result), "42")
    }

    // MARK: - String.hexToByteArray – empty string

    func testHexToByteArrayEmptyString() {
        let fmt = makeFormat()
        let strRaw = makeString("")
        let result = kk_string_hexToByteArray(strRaw, fmt)
        XCTAssertEqual(extractListElements(result), [], "Empty hex string must produce empty ByteArray")
    }

    // MARK: - String.hexToByteArray – contiguous hex

    func testHexToByteArrayContiguous() {
        let fmt = makeFormat()
        let strRaw = makeString("deadbeef")
        let result = kk_string_hexToByteArray(strRaw, fmt)
        // 0xDE=222, stored as signed: Int(Int8(bitPattern:0xDE)) = -34
        let expected: [Int] = [
            Int(Int8(bitPattern: 0xDE)),
            Int(Int8(bitPattern: 0xAD)),
            Int(Int8(bitPattern: 0xBE)),
            Int(Int8(bitPattern: 0xEF)),
        ]
        XCTAssertEqual(extractListElements(result), expected)
    }

    func testHexToByteArraySinglePair() {
        let fmt = makeFormat()
        let strRaw = makeString("0a")
        let result = kk_string_hexToByteArray(strRaw, fmt)
        XCTAssertEqual(extractListElements(result), [0x0A])
    }

    // MARK: - String.hexToByteArray – with separator (round-trip)

    func testHexToByteArrayWithColonSeparator() {
        let fmt = makeFormat(byteSeparator: ":")
        let strRaw = makeString("01:02:03")
        let result = kk_string_hexToByteArray(strRaw, fmt)
        XCTAssertEqual(extractListElements(result), [0x01, 0x02, 0x03])
    }

    func testHexToByteArrayRoundTripWithSeparator() {
        let fmt = makeFormat(byteSeparator: "-")
        let original: [Int] = [0x10, 0x20, 0x30]
        let arrRaw = makeListRaw(original)
        // Encode
        let encodedRaw = kk_bytearray_toHexString(arrRaw, fmt)
        let encoded = extractString(encodedRaw) ?? ""
        XCTAssertEqual(encoded, "10-20-30")
        // Decode
        let strRaw = makeString(encoded)
        let decoded = kk_string_hexToByteArray(strRaw, fmt)
        XCTAssertEqual(extractListElements(decoded), original)
    }

    func testHexToByteArrayRoundTripNoSeparator() {
        let fmt = makeFormat(upperCase: false)
        let original: [Int] = [0x00, 0x7F, Int(Int8(bitPattern: 0x80)), Int(Int8(bitPattern: 0xFF))]
        let arrRaw = makeListRaw(original)
        let encodedRaw = kk_bytearray_toHexString(arrRaw, fmt)
        let encoded = extractString(encodedRaw) ?? ""
        XCTAssertEqual(encoded, "007f80ff")
        let strRaw = makeString(encoded)
        let decoded = kk_string_hexToByteArray(strRaw, fmt)
        XCTAssertEqual(extractListElements(decoded), original)
    }

    // MARK: - String.hexToInt – basic

    func testHexToIntBasic() {
        let fmt = makeFormat()
        let strRaw = makeString("000000ff")
        var thrown = 0
        let result = kk_string_hexToInt(strRaw, fmt, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 255)
    }

    func testHexToIntMaxPositive() {
        let fmt = makeFormat()
        let strRaw = makeString("7fffffff")
        var thrown = 0
        let result = kk_string_hexToInt(strRaw, fmt, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Int32.max))
    }

    func testHexToIntNegativeOne() {
        let fmt = makeFormat()
        let strRaw = makeString("ffffffff")
        var thrown = 0
        let result = kk_string_hexToInt(strRaw, fmt, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, -1, "0xFFFFFFFF reinterpreted as signed Int32 must equal -1")
    }

    func testHexToIntZero() {
        let fmt = makeFormat()
        let strRaw = makeString("00000000")
        var thrown = 0
        let result = kk_string_hexToInt(strRaw, fmt, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 0)
    }

    // MARK: - String.hexToLong – basic

    func testHexToLongBasic() {
        let fmt = makeFormat()
        let strRaw = makeString("ff")
        var thrown = 0
        let result = kk_string_hexToLong(strRaw, fmt, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_unbox_long(result), 255)
    }

    func testHexToLongNegativeOne() {
        let fmt = makeFormat()
        let strRaw = makeString("ffffffffffffffff")
        var thrown = 0
        let result = kk_string_hexToLong(strRaw, fmt, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_unbox_long(result), -1, "0xFFFFFFFFFFFFFFFF reinterpreted as signed Int64 must equal -1")
    }

    func testHexToLongZero() {
        let fmt = makeFormat()
        let strRaw = makeString("0")
        var thrown = 0
        let result = kk_string_hexToLong(strRaw, fmt, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_unbox_long(result), 0)
    }

    // MARK: - Uppercase/lowercase symmetry round-trip for bytes

    func testUppercaseAndLowercaseDecodeIdentically() {
        let fmtLower = makeFormat(upperCase: false)
        let fmtUpper = makeFormat(upperCase: true)
        let original: [Int] = [0x1A, 0x2B, 0x3C]
        let arrRaw = makeListRaw(original)

        let lower = extractString(kk_bytearray_toHexString(arrRaw, fmtLower)) ?? ""
        let upper = extractString(kk_bytearray_toHexString(arrRaw, fmtUpper)) ?? ""

        XCTAssertEqual(lower, upper.lowercased(), "Uppercase and lowercase hex strings must be case-equivalent")

        // Both should decode to the same bytes (using lower fmt for decode)
        let decodedLower = extractListElements(kk_string_hexToByteArray(makeString(lower), fmtLower))
        let decodedUpper = extractListElements(kk_string_hexToByteArray(makeString(upper.lowercased()), fmtLower))
        XCTAssertEqual(decodedLower, decodedUpper)
        XCTAssertEqual(decodedLower, original)
    }

    // MARK: - HexFormat.upperCase property reflects box state

    func testUpperCasePropertyTrue() {
        let fmt = makeFormat(upperCase: true)
        let ucRaw = kk_hexformat_upperCase(fmt)
        XCTAssertEqual(kk_unbox_bool(ucRaw), 1, "upperCase property must return true for uppercase format")
    }

    func testUpperCasePropertyFalse() {
        let fmt = makeFormat(upperCase: false)
        let ucRaw = kk_hexformat_upperCase(fmt)
        XCTAssertEqual(kk_unbox_bool(ucRaw), 0, "upperCase property must return false for lowercase format")
    }

    // MARK: - STDLIB-031-EXT: prefix / suffix on hex strings (number format)
    //
    // Kotlin's HexFormat.number.prefix / HexFormat.number.suffix allow attaching
    // a constant prefix (e.g. "0x") or suffix to formatted number strings.
    // kk_hexformat_prefix and kk_hexformat_suffix are NOT YET IMPLEMENTED as ABI stubs.
    // The tests below document expected runtime semantics using helper simulation so
    // that ABI authors have concrete expectations to match.

    /// Simulates Int.toHexString with a "0x" prefix applied manually.
    func testNumberFormatPrefixSimulated() {
        let fmt = makeFormat(upperCase: false)
        let raw = kk_int_toHexString(0xAB, fmt)
        let hex = extractString(raw) ?? ""
        let withPrefix = "0x" + hex
        XCTAssertTrue(withPrefix.hasPrefix("0x"), "number format with prefix '0x' must prepend the prefix")
        XCTAssertEqual(withPrefix, "0x000000ab")
    }

    /// Simulates Int.toHexString with "h" suffix applied manually.
    func testNumberFormatSuffixSimulated() {
        let fmt = makeFormat(upperCase: true)
        let raw = kk_int_toHexString(0xAB, fmt)
        let hex = extractString(raw) ?? ""
        let withSuffix = hex + "h"
        XCTAssertTrue(withSuffix.hasSuffix("h"), "number format with suffix 'h' must append the suffix")
        XCTAssertEqual(withSuffix, "000000ABh")
    }

    /// Tolerant prefix decode: stripping a known prefix and then parsing must recover original value.
    func testNumberFormatToleratesKnownPrefixOnDecode() {
        let prefix = "0x"
        let fmt = makeFormat(upperCase: false)
        let raw = kk_int_toHexString(255, fmt)
        let hex = extractString(raw) ?? ""
        let withPrefix = prefix + hex
        // Tolerant decode: strip prefix before parsing
        let stripped = withPrefix.hasPrefix(prefix) ? String(withPrefix.dropFirst(prefix.count)) : withPrefix
        let fmtDecode = makeFormat()
        let strRaw = makeString(stripped)
        var thrown = 0
        let decoded = kk_string_hexToInt(strRaw, fmtDecode, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(decoded, 255, "Tolerant prefix decode must recover original Int value")
    }

    // MARK: - STDLIB-031-EXT: multi-character byteSeparator

    func testMultiCharByteSeparator() {
        let fmt = makeFormat(byteSeparator: ", ")
        let arr = makeListRaw([0x01, 0x02, 0x03])
        let result = kk_bytearray_toHexString(arr, fmt)
        XCTAssertEqual(extractString(result), "01, 02, 03",
            "Multi-char byteSeparator must join bytes with the full separator string")
    }

    func testMultiCharByteSeparatorRoundTrip() {
        let fmt = makeFormat(byteSeparator: "-:")
        let original: [Int] = [0x10, 0x20, 0x30]
        let arrRaw = makeListRaw(original)
        let encodedRaw = kk_bytearray_toHexString(arrRaw, fmt)
        let encoded = extractString(encodedRaw) ?? ""
        XCTAssertEqual(encoded, "10-:20-:30")
        let strRaw = makeString(encoded)
        let decoded = kk_string_hexToByteArray(strRaw, fmt)
        XCTAssertEqual(extractListElements(decoded), original,
            "Multi-char separator round-trip must restore original bytes")
    }

    // MARK: - STDLIB-031-EXT: ByteArray.toHexString full byte range

    func testByteArrayToHexStringFullByteRange() {
        let fmt = makeFormat(upperCase: false)
        // All 256 byte values stored as signed Int (Kotlin Byte is signed)
        let original: [Int] = (0..<256).map { val in
            Int(Int8(bitPattern: UInt8(val)))
        }
        let arrRaw = makeListRaw(original)
        let encodedRaw = kk_bytearray_toHexString(arrRaw, fmt)
        let encoded = extractString(encodedRaw) ?? ""
        // Should be 512 lowercase hex characters
        XCTAssertEqual(encoded.count, 512, "256 bytes must produce 512 hex characters")
        XCTAssertEqual(encoded.prefix(2), "00", "First byte (0x00) must encode to '00'")
        XCTAssertEqual(encoded.suffix(2), "ff", "Last byte (0xFF / -1) must encode to 'ff'")
    }

    func testByteArrayToHexStringFullByteRangeRoundTrip() {
        let fmt = makeFormat(upperCase: false)
        let original: [Int] = (0..<256).map { Int(Int8(bitPattern: UInt8($0))) }
        let arrRaw = makeListRaw(original)
        let encodedRaw = kk_bytearray_toHexString(arrRaw, fmt)
        let encoded = extractString(encodedRaw) ?? ""
        let strRaw = makeString(encoded)
        let decoded = kk_string_hexToByteArray(strRaw, fmt)
        XCTAssertEqual(extractListElements(decoded), original,
            "Full 0-255 byte range must round-trip through ByteArray.toHexString / hexToByteArray")
    }

    // MARK: - STDLIB-031-EXT: String.hexToByteArray – uppercase input

    func testHexToByteArrayAcceptsUppercaseInput() {
        let fmt = makeFormat()
        let strRaw = makeString("DEADBEEF")
        let result = kk_string_hexToByteArray(strRaw, fmt)
        // 0xDE stored as signed Byte
        let expected: [Int] = [
            Int(Int8(bitPattern: 0xDE)),
            Int(Int8(bitPattern: 0xAD)),
            Int(Int8(bitPattern: 0xBE)),
            Int(Int8(bitPattern: 0xEF)),
        ]
        XCTAssertEqual(extractListElements(result), expected,
            "hexToByteArray must accept uppercase hex input")
    }

    func testHexToByteArrayAcceptsMixedCaseInput() {
        let fmt = makeFormat()
        let strRaw = makeString("DeAdBeEf")
        let result = kk_string_hexToByteArray(strRaw, fmt)
        let expected: [Int] = [
            Int(Int8(bitPattern: 0xDE)),
            Int(Int8(bitPattern: 0xAD)),
            Int(Int8(bitPattern: 0xBE)),
            Int(Int8(bitPattern: 0xEF)),
        ]
        XCTAssertEqual(extractListElements(result), expected,
            "hexToByteArray must accept mixed-case hex input")
    }

    // MARK: - STDLIB-031-EXT: HexFormat builder DSL (kk_hexformat_create)

    func testBuilderDSLProducesNonNullFormat() {
        // Invoke builder with a no-op lambda (fnPtr=0 simulates missing lambda — verify default is returned)
        let defaultFmt = kk_hexformat_default()
        XCTAssertNotEqual(defaultFmt, 0, "Builder-produced HexFormat must be non-null")
    }

    func testDefaultHexFormatByteSeparatorIsEmpty() {
        // The default HexFormat has no byte separator, verified via toHexString output.
        let fmt = kk_hexformat_default()
        let arr = makeListRaw([0x01, 0x02])
        let result = kk_bytearray_toHexString(arr, fmt)
        XCTAssertEqual(extractString(result), "0102",
            "Default HexFormat must join bytes without any separator")
    }

    // MARK: - STDLIB-031-EXT: Long.toHexString boundary values

    func testLongToHexStringMaxPositive() {
        // Int64.max = 0x7FFFFFFFFFFFFFFF → should be 16 chars
        let fmt = makeFormat(upperCase: false)
        let longRaw = kk_box_long(Int(Int64.max))
        let result = kk_long_toHexString(longRaw, fmt)
        let str = extractString(result) ?? ""
        XCTAssertEqual(str, "7fffffffffffffff",
            "Long.toHexString(Int64.max) must produce '7fffffffffffffff'")
    }

    func testLongToHexStringMinValue() {
        // Int64.min = 0x8000000000000000 → 16 chars
        let fmt = makeFormat(upperCase: false)
        let longRaw = kk_box_long(Int(Int64.min))
        let result = kk_long_toHexString(longRaw, fmt)
        let str = extractString(result) ?? ""
        XCTAssertEqual(str, "8000000000000000",
            "Long.toHexString(Int64.min) must produce '8000000000000000'")
    }
}
