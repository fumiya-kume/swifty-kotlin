@testable import Runtime
import XCTest

/// Edge-case / boundary-value tests for kotlin.uuid.Uuid runtime.
/// Covers STDLIB-UUID-003: runtime / canonical form / failure path.
final class RuntimeUuidEdgeCaseTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
    }

    private func extractRuntimeString(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self) else {
            return ""
        }
        return box.value
    }

    private func extractPairBox(_ raw: Int) -> RuntimePairBox? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
        return tryCast(ptr, to: RuntimePairBox.self)
    }

    private func extractArrayBox(_ raw: Int) -> RuntimeArrayBox? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
        return tryCast(ptr, to: RuntimeArrayBox.self)
    }

    private func intFromBits(_ bits: UInt64) -> Int {
        Int(bitPattern: UInt(bits))
    }

    private func compareWithUuidLexicalOrder(_ lhs: Int, _ rhs: Int) -> Int {
        let comparator = kk_uuid_lexicalOrder()
        let compareFnRaw = kk_itable_lookup(comparator, 0, 0)
        XCTAssertNotEqual(compareFnRaw, 0, "Uuid.LEXICAL_ORDER must register Comparator.compare")
        let compareFn = unsafeBitCast(compareFnRaw, to: RuntimeCollectionLambda2.self)
        var thrown = 0
        let result = compareFn(comparator, lhs, rhs, &thrown)
        XCTAssertEqual(thrown, 0)
        return result
    }

    // MARK: - Canonical Form (8-4-4-4-12 lowercase)

    /// toString must emit lowercase hex digits regardless of how the UUID was created.
    func testToStringAlwaysEmitsLowercase() {
        // Parse with uppercase input (Kotlin's parser is case-insensitive)
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("123E4567-E89B-12D3-A456-426614174000"), &thrown)
        XCTAssertEqual(thrown, 0, "Parsing uppercase UUID string should succeed")
        let str = extractRuntimeString(kk_uuid_toString(uuidRaw))
        XCTAssertEqual(str, "123e4567-e89b-12d3-a456-426614174000", "toString must emit lowercase")
    }

    /// toString must produce exactly the 8-4-4-4-12 canonical hyphenated form.
    func testToStringProducesCanonicalForm() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("550e8400-e29b-41d4-a716-446655440000"), &thrown)
        XCTAssertEqual(thrown, 0)
        let str = extractRuntimeString(kk_uuid_toString(uuidRaw))

        XCTAssertEqual(str.count, 36, "Canonical UUID string must be 36 characters")
        XCTAssertEqual(str[str.index(str.startIndex, offsetBy: 8)], "-")
        XCTAssertEqual(str[str.index(str.startIndex, offsetBy: 13)], "-")
        XCTAssertEqual(str[str.index(str.startIndex, offsetBy: 18)], "-")
        XCTAssertEqual(str[str.index(str.startIndex, offsetBy: 23)], "-")

        let parts = str.split(separator: "-", omittingEmptySubsequences: false)
        XCTAssertEqual(parts.count, 5)
        XCTAssertEqual(parts[0].count, 8)
        XCTAssertEqual(parts[1].count, 4)
        XCTAssertEqual(parts[2].count, 4)
        XCTAssertEqual(parts[3].count, 4)
        XCTAssertEqual(parts[4].count, 12)
    }

    /// Round-trip: parse canonical string -> toString == original (lowercase).
    func testCanonicalStringRoundTrip() {
        let inputs = [
            "00000000-0000-0000-0000-000000000000",
            "ffffffff-ffff-ffff-ffff-ffffffffffff",
            "123e4567-e89b-12d3-a456-426614174000",
        ]
        for input in inputs {
            var thrown = 0
            let uuidRaw = kk_uuid_parse(makeRuntimeString(input), &thrown)
            XCTAssertEqual(thrown, 0, "Should parse: \(input)")
            let output = extractRuntimeString(kk_uuid_toString(uuidRaw))
            XCTAssertEqual(output, input, "Round-trip failed for \(input)")
        }
    }

    // MARK: - NIL UUID (all zeros)

    func testNilUuidAllZeros() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("00000000-0000-0000-0000-000000000000"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(extractRuntimeString(kk_uuid_toString(uuidRaw)),
                       "00000000-0000-0000-0000-000000000000")
        XCTAssertEqual(kk_uuid_mostSignificantBits(uuidRaw), 0)
        XCTAssertEqual(kk_uuid_leastSignificantBits(uuidRaw), 0)
    }

    func testNilUuidHexStringAllZeros() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("00000000-0000-0000-0000-000000000000"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(extractRuntimeString(kk_uuid_toHexString(uuidRaw)),
                       "00000000000000000000000000000000")
    }

    func testLexicalOrderComparatorUsesUnsignedUuidBits() {
        let nilUuid = kk_uuid_fromLongs(0, 0)
        let one = kk_uuid_fromLongs(0, 1)
        let signedNegativeMsb = kk_uuid_fromLongs(intFromBits(0x8000_0000_0000_0000), 0)
        let signedPositiveMsb = kk_uuid_fromLongs(intFromBits(0x7fff_ffff_ffff_ffff), 0)

        XCTAssertLessThan(compareWithUuidLexicalOrder(nilUuid, one), 0)
        XCTAssertGreaterThan(compareWithUuidLexicalOrder(one, nilUuid), 0)
        XCTAssertEqual(compareWithUuidLexicalOrder(one, one), 0)
        XCTAssertGreaterThan(
            compareWithUuidLexicalOrder(signedNegativeMsb, signedPositiveMsb),
            0,
            "UUID lexical ordering compares the 128-bit value unsigned, not Swift signed Int order"
        )
    }

    // MARK: - MAX UUID (all Fs)

    func testMaxUuidAllFs() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("ffffffff-ffff-ffff-ffff-ffffffffffff"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(extractRuntimeString(kk_uuid_toString(uuidRaw)),
                       "ffffffff-ffff-ffff-ffff-ffffffffffff")
        // MSB and LSB should both be -1 when interpreted as Int64 (all bits set)
        XCTAssertEqual(UInt64(bitPattern: Int64(kk_uuid_mostSignificantBits(uuidRaw))),
                       UInt64.max)
        XCTAssertEqual(UInt64(bitPattern: Int64(kk_uuid_leastSignificantBits(uuidRaw))),
                       UInt64.max)
    }

    func testMaxUuidHexString() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("ffffffff-ffff-ffff-ffff-ffffffffffff"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(extractRuntimeString(kk_uuid_toHexString(uuidRaw)),
                       "ffffffffffffffffffffffffffffffff")
    }

    // MARK: - toHexString round-trip

    func testHexStringRoundTrip() {
        let hexInput = "123e4567e89b12d3a456426614174000"
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString(hexInput), &thrown)
        XCTAssertEqual(thrown, 0)
        let hexOut = extractRuntimeString(kk_uuid_toHexString(uuidRaw))
        XCTAssertEqual(hexOut, hexInput, "toHexString must match original hex input")
        // Re-parse the hex output and verify canonical form
        let uuidRaw2 = kk_uuid_parse(makeRuntimeString(hexOut), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(extractRuntimeString(kk_uuid_toString(uuidRaw2)),
                       "123e4567-e89b-12d3-a456-426614174000")
    }

    // MARK: - toLongs / fromLongs endianness round-trip

    /// toLongs should return (mostSignificantBits, leastSignificantBits) in that order.
    func testToLongsEndianness() {
        var thrown = 0
        // 550e8400-e29b-41d4 -> msb = 0x550e8400e29b41d4
        // a716-446655440000  -> lsb = 0xa716446655440000
        let uuidRaw = kk_uuid_parse(makeRuntimeString("550e8400-e29b-41d4-a716-446655440000"), &thrown)
        XCTAssertEqual(thrown, 0)

        let pairRaw = kk_uuid_toLongs(uuidRaw)
        let msb = kk_pair_first(pairRaw)
        let lsb = kk_pair_second(pairRaw)

        XCTAssertEqual(UInt64(bitPattern: Int64(msb)), 0x550e8400e29b41d4,
                       "First element of toLongs must be most significant bits")
        XCTAssertEqual(UInt64(bitPattern: Int64(lsb)), 0xa716446655440000,
                       "Second element of toLongs must be least significant bits")
    }

    /// toLongs on NIL UUID should return (0, 0).
    func testToLongsNilUuid() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("00000000-0000-0000-0000-000000000000"), &thrown)
        XCTAssertEqual(thrown, 0)
        let pairRaw = kk_uuid_toLongs(uuidRaw)
        XCTAssertEqual(kk_pair_first(pairRaw), 0)
        XCTAssertEqual(kk_pair_second(pairRaw), 0)
    }

    // MARK: - toByteArray (big-endian)

    /// toByteArray must return 16 bytes in big-endian order.
    func testToByteArrayLength() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("123e4567-e89b-12d3-a456-426614174000"), &thrown)
        XCTAssertEqual(thrown, 0)
        let arrayRaw = kk_uuid_toByteArray(uuidRaw)
        guard let arrayBox = extractArrayBox(arrayRaw) else {
            XCTFail("toByteArray returned invalid array handle")
            return
        }
        XCTAssertEqual(arrayBox.elements.count, 16, "toByteArray must return exactly 16 bytes")
    }

    /// toByteArray big-endian order: first byte is MSB high byte.
    func testToByteArrayBigEndian() {
        // UUID: 550e8400-e29b-41d4-a716-446655440000
        // Bytes (big-endian): 55 0e 84 00  e2 9b 41 d4  a7 16 44 66  55 44 00 00
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("550e8400-e29b-41d4-a716-446655440000"), &thrown)
        XCTAssertEqual(thrown, 0)
        let arrayRaw = kk_uuid_toByteArray(uuidRaw)
        guard let arrayBox = extractArrayBox(arrayRaw) else {
            XCTFail("toByteArray returned invalid array handle")
            return
        }
        let expected: [UInt8] = [
            0x55, 0x0e, 0x84, 0x00,
            0xe2, 0x9b, 0x41, 0xd4,
            0xa7, 0x16, 0x44, 0x66,
            0x55, 0x44, 0x00, 0x00,
        ]
        for (i, expectedByte) in expected.enumerated() {
            XCTAssertEqual(UInt8(arrayBox.elements[i] & 0xFF), expectedByte,
                           "Byte \(i) mismatch")
        }
    }

    /// NIL UUID byte array must be all zeros.
    func testToByteArrayNilUuidAllZeros() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("00000000-0000-0000-0000-000000000000"), &thrown)
        XCTAssertEqual(thrown, 0)
        let arrayRaw = kk_uuid_toByteArray(uuidRaw)
        guard let arrayBox = extractArrayBox(arrayRaw) else {
            XCTFail("toByteArray returned invalid array handle")
            return
        }
        for i in 0..<16 {
            XCTAssertEqual(arrayBox.elements[i], 0, "Byte \(i) must be 0 for NIL UUID")
        }
    }

    // MARK: - Failure Paths

    /// Too-short string must throw.
    func testParseTooShortStringThrows() {
        var thrown = 0
        let result = kk_uuid_parse(makeRuntimeString("123e4567-e89b-12d3"), &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "Too-short string must throw")
    }

    /// Too-long string must throw.
    func testParseTooLongStringThrows() {
        var thrown = 0
        let longStr = "123e4567-e89b-12d3-a456-426614174000-extra"
        let result = kk_uuid_parse(makeRuntimeString(longStr), &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "Too-long string must throw")
    }

    /// Invalid hex characters in a 36-character string must throw.
    func testParseInvalidHexCharsThrows() {
        var thrown = 0
        let bad = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        let result = kk_uuid_parse(makeRuntimeString(bad), &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "Invalid hex chars must throw")
    }

    /// Missing dashes (31 hex chars) must throw.
    func testParseMissingDashesThrows() {
        var thrown = 0
        // 31 chars — not 32 (hex) nor 36 (dashed)
        let noDash = "123e4567e89b12d3a45642661417400"
        let result = kk_uuid_parse(makeRuntimeString(noDash), &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "31-char string (not 32 hex) must throw")
    }

    /// Extra dashes must throw.
    func testParseExtraDashesThrows() {
        var thrown = 0
        // Correct length but wrong dash positions
        let extraDash = "123e-4567-e89b-12d3-a456426614174"
        let result = kk_uuid_parse(makeRuntimeString(extraDash), &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "Wrong dash positions must throw")
    }

    /// Empty string must throw.
    func testParseEmptyStringThrows() {
        var thrown = 0
        let result = kk_uuid_parse(makeRuntimeString(""), &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "Empty string must throw")
    }

    /// 32-char string with invalid hex char must throw.
    func testParseHex32WithInvalidCharThrows() {
        var thrown = 0
        // 32 chars but one 'g' which is not hex
        let bad = "123e4567e89b12d3a45642661417400g"
        let result = kk_uuid_parse(makeRuntimeString(bad), &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "32-char string with invalid hex char must throw")
    }

    // MARK: - Uppercase input is case-insensitive

    func testParseUppercaseHexStringSucceeds() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("123E4567E89B12D3A456426614174000"), &thrown)
        XCTAssertEqual(thrown, 0, "Uppercase 32-char hex string must parse successfully")
        // toString must still emit lowercase
        let str = extractRuntimeString(kk_uuid_toString(uuidRaw))
        XCTAssertEqual(str, "123e4567-e89b-12d3-a456-426614174000")
    }

    // MARK: - version() / variant() on special UUIDs

    func testNilUuidVersionAndVariant() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("00000000-0000-0000-0000-000000000000"), &thrown)
        XCTAssertEqual(thrown, 0)
        // NIL UUID: version bits are 0
        XCTAssertEqual(kk_uuid_version(uuidRaw), 0)
    }

    func testMaxUuidVersion() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("ffffffff-ffff-ffff-ffff-ffffffffffff"), &thrown)
        XCTAssertEqual(thrown, 0)
        // MAX UUID: version bits are 0xF = 15
        XCTAssertEqual(kk_uuid_version(uuidRaw), 15)
    }

    // MARK: - Random UUID uniqueness

    func testRandomUuidsAreUnique() {
        let uuid1 = kk_uuid_random()
        let uuid2 = kk_uuid_random()
        let str1 = extractRuntimeString(kk_uuid_toString(uuid1))
        let str2 = extractRuntimeString(kk_uuid_toString(uuid2))
        XCTAssertNotEqual(str1, str2, "Two random UUIDs must not be equal")
    }

    func testRandomUuidIsVersion4() {
        let uuidRaw = kk_uuid_random()
        XCTAssertEqual(kk_uuid_version(uuidRaw), 4)
    }

    func testRandomUuidIsRFCVariant() {
        let uuidRaw = kk_uuid_random()
        XCTAssertEqual(kk_uuid_variant(uuidRaw), 2)
    }
}
