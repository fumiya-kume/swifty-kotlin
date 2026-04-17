@testable import Runtime
import XCTest

/// Tests for kk_uuid_fromLongs and kk_uuid_fromByteArray (STDLIB-UUID-ABI-001/002).
final class RuntimeUuidFromLongsFromByteArrayTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - Uuid.fromLongs round-trip

    func testFromLongsRoundTripWithToLongs() {
        // Create a UUID via fromLongs and verify toLongs gives back the same values.
        let msb = Int(bitPattern: UInt(0x550e8400e29b41d4))
        let lsb = Int(bitPattern: UInt(0xa716446655440000))

        let uuidRaw = kk_uuid_fromLongs(msb, lsb)
        XCTAssertNotEqual(uuidRaw, 0, "fromLongs must return a valid handle")

        let pair = kk_uuid_toLongs(uuidRaw)
        guard let pairPtr = UnsafeMutableRawPointer(bitPattern: pair),
              let pairBox = tryCast(pairPtr, to: RuntimePairBox.self)
        else {
            XCTFail("toLongs did not return a valid pair handle"); return
        }

        XCTAssertEqual(pairBox.first, msb, "MSB round-trip mismatch")
        XCTAssertEqual(pairBox.second, lsb, "LSB round-trip mismatch")
    }

    func testFromLongsProducesCorrectUuidString() {
        // 550e8400-e29b-41d4-a716-446655440000
        let msb = Int(bitPattern: UInt(0x550e8400e29b41d4))
        let lsb = Int(bitPattern: UInt(0xa716446655440000))

        let uuidRaw = kk_uuid_fromLongs(msb, lsb)

        guard let ptr = UnsafeMutableRawPointer(bitPattern: kk_uuid_toString(uuidRaw)),
              let stringBox = tryCast(ptr, to: RuntimeStringBox.self)
        else {
            XCTFail("toString did not return a valid string handle"); return
        }

        XCTAssertEqual(stringBox.value, "550e8400-e29b-41d4-a716-446655440000")
    }

    func testFromLongsZeroProducesNilUuid() {
        let uuidRaw = kk_uuid_fromLongs(0, 0)
        XCTAssertNotEqual(uuidRaw, 0, "fromLongs(0, 0) must return a valid handle (Uuid.NIL)")

        guard let ptr = UnsafeMutableRawPointer(bitPattern: kk_uuid_toString(uuidRaw)),
              let stringBox = tryCast(ptr, to: RuntimeStringBox.self)
        else {
            XCTFail("toString failed"); return
        }

        XCTAssertEqual(stringBox.value, "00000000-0000-0000-0000-000000000000")
    }

    // MARK: - Uuid.fromByteArray round-trip

    func testFromByteArrayRoundTripWithToByteArray() {
        // Create a UUID via random, convert to byte array, then reconstruct and verify.
        let originalRaw = kk_uuid_random()
        let byteArrayRaw = kk_uuid_toByteArray(originalRaw)

        var thrown = 0
        let reconstructedRaw = kk_uuid_fromByteArray(byteArrayRaw, &thrown)

        XCTAssertEqual(thrown, 0, "fromByteArray must not throw for a valid 16-byte array")
        XCTAssertNotEqual(reconstructedRaw, 0)

        XCTAssertEqual(
            kk_uuid_mostSignificantBits(originalRaw),
            kk_uuid_mostSignificantBits(reconstructedRaw),
            "MSB mismatch after byte-array round-trip"
        )
        XCTAssertEqual(
            kk_uuid_leastSignificantBits(originalRaw),
            kk_uuid_leastSignificantBits(reconstructedRaw),
            "LSB mismatch after byte-array round-trip"
        )
    }

    func testFromByteArrayKnownValues() {
        // 550e8400-e29b-41d4-a716-446655440000
        // MSB bytes (big-endian): 55 0e 84 00 e2 9b 41 d4
        // LSB bytes (big-endian): a7 16 44 66 55 44 00 00
        let expectedBytes: [Int] = [
            0x55, 0x0e, 0x84, 0x00, 0xe2, 0x9b, 0x41, 0xd4,
            0xa7, 0x16, 0x44, 0x66, 0x55, 0x44, 0x00, 0x00
        ]
        let arrayBox = RuntimeArrayBox(length: 16)
        for i in 0..<16 {
            arrayBox.elements[i] = expectedBytes[i]
        }
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrown = 0
        let uuidRaw = kk_uuid_fromByteArray(arrayRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        guard let ptr = UnsafeMutableRawPointer(bitPattern: kk_uuid_toString(uuidRaw)),
              let stringBox = tryCast(ptr, to: RuntimeStringBox.self)
        else {
            XCTFail("toString failed"); return
        }

        XCTAssertEqual(stringBox.value, "550e8400-e29b-41d4-a716-446655440000")
    }

    func testFromByteArrayWrongSizeThrows() {
        // Array with 10 bytes — must throw IllegalArgumentException.
        let arrayBox = RuntimeArrayBox(length: 10)
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrown = 0
        let uuidRaw = kk_uuid_fromByteArray(arrayRaw, &thrown)

        XCTAssertEqual(uuidRaw, 0, "fromByteArray must return 0 on size mismatch")
        XCTAssertNotEqual(thrown, 0, "fromByteArray must throw for wrong-size array")
    }

    func testFromByteArraySizeZeroThrows() {
        let arrayBox = RuntimeArrayBox(length: 0)
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrown = 0
        let uuidRaw = kk_uuid_fromByteArray(arrayRaw, &thrown)

        XCTAssertEqual(uuidRaw, 0)
        XCTAssertNotEqual(thrown, 0, "fromByteArray must throw for empty array")
    }

    func testFromByteArraySizeTooLargeThrows() {
        let arrayBox = RuntimeArrayBox(length: 17)
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrown = 0
        let uuidRaw = kk_uuid_fromByteArray(arrayRaw, &thrown)

        XCTAssertEqual(uuidRaw, 0)
        XCTAssertNotEqual(thrown, 0, "fromByteArray must throw for 17-byte array")
    }

    // MARK: - fromLongs → toByteArray → fromByteArray full round-trip

    func testFullRoundTripFromLongsThroughByteArray() {
        let msb = Int(bitPattern: UInt(0x123e4567e89b12d3))
        let lsb = Int(bitPattern: UInt(0xa456426614174000))

        let uuidRaw = kk_uuid_fromLongs(msb, lsb)
        let byteArrayRaw = kk_uuid_toByteArray(uuidRaw)

        var thrown = 0
        let reconstructed = kk_uuid_fromByteArray(byteArrayRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(kk_uuid_mostSignificantBits(reconstructed), msb)
        XCTAssertEqual(kk_uuid_leastSignificantBits(reconstructed), lsb)
    }
}
