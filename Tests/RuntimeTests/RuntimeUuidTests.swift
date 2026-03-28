@testable import Runtime
import XCTest

final class RuntimeUuidTests: XCTestCase {
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

    private func extractRuntimeString(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self) else {
            return ""
        }
        return box.value
    }

    func testRandomUuidFormatsAsVersion4String() {
        let uuidRaw = kk_uuid_random()
        let rendered = extractRuntimeString(kk_uuid_toString(uuidRaw))

        XCTAssertEqual(rendered.count, 36)
        XCTAssertEqual(rendered[rendered.index(rendered.startIndex, offsetBy: 14)], "4")

        let variant = rendered[rendered.index(rendered.startIndex, offsetBy: 19)].lowercased()
        XCTAssertTrue(["8", "9", "a", "b"].contains(variant))
    }

    func testParseRoundTripsStandardString() {
        let input = "123e4567-e89b-12d3-a456-426614174000"
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString(input), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(extractRuntimeString(kk_uuid_toString(uuidRaw)), input)
    }

    func testParseAcceptsHexString() {
        let input = "123e4567e89b12d3a456426614174000"
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString(input), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(extractRuntimeString(kk_uuid_toHexString(uuidRaw)), input)
        XCTAssertEqual(
            extractRuntimeString(kk_uuid_toString(uuidRaw)),
            "123e4567-e89b-12d3-a456-426614174000"
        )
    }

    func testParseInvalidStringThrows() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("not-a-uuid"), &thrown)

        XCTAssertEqual(uuidRaw, 0)
        XCTAssertNotEqual(thrown, 0)
    }
}
