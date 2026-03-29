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
}
