@testable import Runtime
import XCTest

final class RuntimeUuidAdvancedTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
    }

    func testRandomUuidReportsVersion4AndRfcVariant() {
        let uuidRaw = kk_uuid_random()
        XCTAssertEqual(kk_uuid_version(uuidRaw), 4)
        XCTAssertEqual(kk_uuid_variant(uuidRaw), 2)
    }

    func testParsedUuidExposesVersionAndVariant() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("123e4567-e89b-12d3-a456-426614174000"), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_uuid_version(uuidRaw), 1)
        XCTAssertEqual(kk_uuid_variant(uuidRaw), 2)
    }

    func testMostSignificantBitsMatchesExpected() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("550e8400-e29b-41d4-a716-446655440000"), &thrown)
        XCTAssertEqual(thrown, 0)
        let msb = kk_uuid_mostSignificantBits(uuidRaw)
        // 550e8400-e29b-41d4 -> msb = 0x550e8400e29b41d4
        XCTAssertEqual(UInt64(bitPattern: Int64(msb)), 0x550e8400e29b41d4)
    }

    func testLeastSignificantBitsMatchesExpected() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("550e8400-e29b-41d4-a716-446655440000"), &thrown)
        XCTAssertEqual(thrown, 0)
        let lsb = kk_uuid_leastSignificantBits(uuidRaw)
        // a716-446655440000 -> lsb = 0xa716446655440000
        XCTAssertEqual(UInt64(bitPattern: Int64(lsb)), 0xa716446655440000)
    }

    func testNameUUIDFromBytesIsDeterministic() {
        let nameArr = RuntimeArrayBox(length: 5)
        for i in 0..<5 {
            nameArr.elements[i] = i + 1
        }
        let rawArr = registerRuntimeObject(nameArr)

        let uuid1 = kk_uuid_nameUUIDFromBytes(rawArr)
        let uuid2 = kk_uuid_nameUUIDFromBytes(rawArr)

        XCTAssertEqual(kk_uuid_version(uuid1), 3)
        XCTAssertEqual(kk_uuid_variant(uuid1), 2)
        XCTAssertEqual(kk_uuid_mostSignificantBits(uuid1), kk_uuid_mostSignificantBits(uuid2))
        XCTAssertEqual(kk_uuid_leastSignificantBits(uuid1), kk_uuid_leastSignificantBits(uuid2))
    }
}
